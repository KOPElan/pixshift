# PixShift 技术设计

## 1. 技术基线

- UI：SwiftUI，必要处桥接 AppKit。
- 语言：Swift 6，启用严格并发检查。
- 最低部署目标：macOS 15。
- 构建环境：Xcode 26。
- 架构：单窗口应用，特性分层；不引入跨平台 UI 框架。
- 沙盒：从首版开始启用 App Sandbox 和用户选择文件的读写权限，为 Mac App Store 做准备。

### 系统框架

- SwiftUI / AppKit：窗口、设置、文件选择、拖放和 Finder 集成。
- UniformTypeIdentifiers：格式识别。
- Image I/O：读取图片、缩略图、元数据以及 JPEG/PNG/HEIC/TIFF 编码。
- Core Image / Core Graphics：方向归一化、裁剪、缩放、色彩空间和透明背景合成。
- OSLog：本地诊断日志，不写入文件路径等敏感信息。

Apple 将 Image I/O 定义为可高效读写大多数图片格式并处理色彩与元数据的系统框架；`CGImageDestination` 提供输出类型查询、压缩质量、背景色与排除 GPS 元数据等能力。[Apple Image I/O](https://developer.apple.com/documentation/imageio) · [CGImageDestination](https://developer.apple.com/documentation/imageio/cgimagedestination)

## 2. WebP 决策

`UTType.webP` 只表示系统认识 WebP 类型，不保证 Image I/O 有 WebP 编码器。Apple 文档提供 `CGImageDestinationCopyTypeIdentifiers()` 用于查询实际可输出类型。[Apple UTType WebP](https://developer.apple.com/documentation/uniformtypeidentifiers/uttypewebp) · [Apple CGImageDestination](https://developer.apple.com/documentation/imageio/cgimagedestination)

在当前 macOS 26.6 开发机实测：Image I/O 可输出 JPEG、PNG、HEIC、TIFF，但 `org.webmproject.webp` 不在输出类型列表中。因此：

- WebP 解码优先使用 Image I/O。
- WebP 编码使用随应用内置的官方 `libwebp` 静态库/XCFramework。
- 通过很薄的 C target 暴露编码和 metadata mux 能力给 Swift。
- 不调用 Homebrew、不启动 `cwebp` 子进程、不依赖用户环境。
- 固定并记录 `libwebp` 版本，保留 BSD-3-Clause license 与 notices。
- CI 对 arm64 与 x86_64 构建、符号和 App Store 签名做验证。

官方 `libwebp` 提供 RGBA/BGRA 有损与无损编码 API，品质范围为 0–100；高级 API 可控制编码参数。[libwebp API](https://github.com/webmproject/libwebp/blob/main/doc/api.md)

## 3. 模块结构

```text
PixShiftApp
├── AppShell
│   ├── MainWindow
│   ├── SettingsScene
│   └── Localization
├── ImportFeature
│   ├── ImportCoordinator
│   ├── DirectoryScanner
│   └── ThumbnailService
├── BatchConfiguration
│   ├── ResizePolicy
│   ├── CropPolicy
│   ├── ExportPolicy
│   └── NamingTemplate
├── CropEditor
│   ├── CropCanvas
│   └── NormalizedCropGeometry
├── ProcessingEngine
│   ├── BatchCoordinator
│   ├── ImageDecoder
│   ├── TransformPipeline
│   ├── NativeImageEncoder
│   ├── WebPEncoder
│   └── RunLedger
├── Persistence
│   ├── SettingsStore
│   ├── SecurityBookmarkStore
│   └── LocalSuccessCounter
└── Support
    ├── FileAccess
    ├── Diagnostics
    └── ErrorPresentation
```

核心模型与处理引擎不依赖 SwiftUI，便于单元测试和未来增加命令行能力，但首版不交付 CLI。

## 4. 核心数据模型

```swift
struct ImageJob: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let sourceType: UTType
    let pixelSize: CGSize
    let hasAlpha: Bool
    let importIndex: Int
}

enum ResizeMode: Sendable, Equatable {
    case exact(width: Int, height: Int)
    case percentage(Double)
    case fixedWidth(Int)
    case fixedHeight(Int)
    case longestEdge(Int)
    case shortestEdge(Int)
}

struct CropPolicy: Sendable, Equatable {
    let aspectRatio: Double?
    let normalizedRect: CGRect
}

struct ExportPolicy: Sendable, Equatable {
    let format: ExportFormat
    let lossyQuality: Double
    let jpegBackground: CGColor
    let destination: DestinationPolicy
    let namingTemplate: String
}
```

持久化时不直接编码 `CGColor`、`UTType` 等框架对象，转换成稳定的 Codable 值对象。

## 5. 图片处理流水线

每张图的步骤：

1. 建立安全作用域文件访问。
2. 使用 `CGImageSource` 读取属性、方向、色彩配置与元数据。
3. 按 EXIF orientation 将像素坐标归一化。
4. 根据批次策略计算源像素裁剪矩形。
5. 执行裁剪。
6. 使用高质量插值缩放至目标尺寸。
7. 目标为 JPEG 且存在 alpha 时，在指定背景色上合成。
8. 复制允许的元数据、排除 GPS、规范化 orientation。
9. 将同目标目录下不可预测的唯一临时文件预写入本轮任务台账。
10. 编码到临时文件，finalize 成功后把带文件身份的最终路径预写入台账。
11. 原子移动到预检确定的最终名称，再从台账移除临时文件记录。

对于大幅缩小的图片，优先让 Image I/O 生成接近目标尺寸的缩略解码，避免先解码完整超大位图；需要精确裁剪时根据裁剪区域反推安全解码尺寸。放大或高精度裁剪时使用完整源像素。

## 6. 尺寸与裁剪算法

### 6.1 尺寸

- 百分比：`round(source × percent / 100)`。
- 固定宽/高：按已校正方向后的原比例计算另一边。
- 最长边：比例 `target / max(width, height)`。
- 最短边：比例 `target / min(width, height)`。
- 禁止放大时，比例上限为 1。
- exact 模式先计算覆盖目标比例的最大源裁剪矩形，再缩放到精确目标尺寸。

所有浮点结果在最终像素边界使用一致的四舍五入规则并限制最小值为 1，避免 UI 摘要与实际输出不一致。

### 6.2 自定义裁剪

裁剪编辑器存储 `[0, 1]` 坐标系中的 `normalizedRect`。应用到每张图片时：

1. 映射到方向归一化后的源像素范围。
2. 根据目标比例修正宽或高。
3. 保持归一化中心点不变。
4. 若越界则向内平移，不缩小、不改变比例。
5. 对齐整数像素边界。

这保证混合尺寸图片使用相同的相对构图位置，同时不会生成越界裁剪。

## 7. 并发、内存与取消

- `BatchCoordinator` 使用结构化并发和有界 task group；只在一个任务结束后补充下一个任务，避免一次性启动整个队列。
- 默认并发度根据活动 CPU 与物理内存分档计算，限制在 2–4；UI 不暴露该设置。
- 调度器创建固定数量的工作槽；每个槽复用独立的图片处理器与 `CIContext`，命名分配和运行台账仍由 actor 串行保护。
- 不在内存中保留完整输出数组；一张图片完成后立即释放大像素缓冲。
- 进度状态由 actor 隔离，通过主 actor 发布轻量快照。
- 每个阶段检查 `Task.isCancelled`；无法中断的系统编码结束后不再提交输出。

取消流程：

1. coordinator 标记取消并取消子任务。
2. 等待正在写入的临时文件退出安全点。
3. 从 `RunLedger` 读取本轮临时文件和已提交输出。
4. 删除台账中的文件并逐项记录结果。
5. 全部成功才返回 `cancelledAndCleaned`；否则返回带遗留清单的结果。

`RunLedger` 采用预写方式持久化到 Application Support：创建临时文件前记录临时路径，提交最终文件前记录其预期路径及临时文件的设备号与 inode。若应用意外退出，下次启动可识别未完成任务并询问用户是否清理；最终输出只有在文件身份仍匹配时才会删除，避免误删后来出现的同名文件。

## 8. 文件访问与沙盒

- 启用 `com.apple.security.files.user-selected.read-write`。
- `NSOpenPanel` 支持多选文件或目录；文件夹扫描由应用执行。
- 拖放 URL 和打开面板 URL 在使用期间调用安全作用域访问 API。
- 统一输出目录保存 security-scoped bookmark；书签失效时重新请求授权。
- 默认写入原目录前逐个验证父目录权限。只选中单文件时，沙盒授权可能不包含创建同级文件的权限，因此必要时请求用户选择父目录授权。
- 不在未授权位置降级写入，也不静默改用其他目录。

## 9. 编码与元数据

### 原生编码器

- 启动时读取 `CGImageDestinationCopyTypeIdentifiers()`，确认 JPEG/PNG/HEIC/TIFF 可写。
- JPEG、HEIC 使用 `kCGImageDestinationLossyCompressionQuality`。
- 使用 Image I/O 元数据接口复制兼容字段。
- 使用 `kCGImageMetadataShouldExcludeGPS` 排除 GPS。
- ICC profile 随色彩管理流水线保留；格式转换不支持时转换到 Display P3 或 sRGB 的明确目标空间，默认优先保留原空间。

### WebP 编码器

- 输入为明确色彩空间的连续 RGBA/BGRA 缓冲。
- `libwebp` 品质映射 1–100。
- 使用 mux API 写入 ICC、EXIF/XMP 的允许子集，写入前移除 GPS。
- 首版仅输出静态 WebP。
- WebP 单边尺寸受 codec 限制；超出时在预检中给出明确错误。官方编码头文件规定最大边小于 16384。[libwebp encode.h](https://github.com/webmproject/libwebp/blob/main/src/webp/encode.h)

## 10. 命名与原子写入

- 预检阶段对所有任务渲染命名模板，并对磁盘现有文件和批次内部名称同时去重。
- `index` 宽度为 `max(3, totalCount 的十进制位数)`。
- 临时文件名使用不可预测 UUID，并放在最终目录，保证原子 rename 不跨卷。
- 只有编码 finalize 和文件同步成功后才移动到最终 URL。
- 不覆盖；若预检后出现外部竞争导致目标名被占用，执行时再次选择后缀并更新台账。

## 11. 持久化

- `UserDefaults`：轻量设置、上次参数、本机成功计数。
- Application Support：安全作用域书签、未完成任务台账。
- 不保存导入文件路径或历史任务。
- 成功计数使用批次最终提交：任务正常结束后增加成功输出数；取消并清理的任务不增加。

## 12. 错误类型

使用结构化错误并映射为本地化文案：

- unsupportedFormat
- unreadableSource
- invalidDimensions
- cropOutOfBounds
- encoderUnavailable
- webPDimensionLimit
- destinationPermissionDenied
- filenameInvalid
- diskFull
- encodeFailed
- metadataWriteFailed
- cancelled
- cleanupFailed

内部错误可写入统一日志，但 UI 不展示底层堆栈或敏感路径；用户主动展开失败详情时可显示对应文件位置。

## 13. 测试策略

### 单元测试

- 所有尺寸模式、禁止/允许放大、1 px 边界。
- 横图、竖图、不同 EXIF orientation 的裁剪映射。
- 归一化裁剪越界修正。
- 命名模板、非法字符、批次内/磁盘冲突。
- 元数据 GPS 清除与允许字段保留。
- 成功计数的完成、部分失败与取消语义。

### 集成测试

- 五种格式的读入与导出矩阵。
- 透明 PNG/WEBP 转 JPEG 的背景合成。
- WebP 品质与尺寸边界。
- 无权限、损坏文件、磁盘不足、编码失败时继续队列。
- 取消时只删除本轮文件，保留原图和预先存在文件。
- 安全作用域书签失效和重新授权。

### UI 测试

- 三种导入入口。
- 尺寸模式切换与验证。
- 裁剪控制柄和键盘操作。
- 进度、取消、清理与失败清单。
- 简体中文、英文及较长英文文本布局。

### 性能测试

- 1,000 张常规照片的稳定队列。
- 超大分辨率图片的峰值内存。
- 混合格式、混合方向批次。
- 与串行基线比较吞吐，同时确认 UI 无明显卡顿。
