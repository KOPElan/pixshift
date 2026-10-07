# PixShift: Resize & Convert Images

PixShift 是一款使用 SwiftUI 构建的原生 macOS 批量图片处理工具，支持批量调整尺寸、裁剪、格式转换与导出。所有图片处理均在本机完成。

当前仓库已经进入可运行的 MVP 开发阶段：导入队列、尺寸处理、五种格式导出、命名避让、有界并发、进度、取消清理与异常退出恢复主链路已经接通。

## 主要功能

- **批量导入**：选择文件、选择文件夹，或从 Finder 拖放导入；文件夹仅扫描当前层，跳过隐藏文件。
- **六种尺寸模式**：指定宽高、百分比、固定宽度、固定高度、最长边、最短边；可选择是否允许放大。
- **统一裁剪**：支持原始、自由、预设与自定义比例，提供裁剪定位画布，并将裁剪设置映射到整批图片。
- **五种格式**：支持 JPEG、PNG、WebP、HEIC、TIFF 的读取与导出，可保持原格式或批量转换；JPEG、WebP、HEIC 支持品质设置。
- **灵活导出**：输出到原图各自目录或统一目录；支持命名模板，同名文件自动添加后缀，避免覆盖已有文件。
- **批处理管理**：2–4 路自适应有界并发、处理进度、失败清单、取消后清理，以及异常退出后的未完成批次恢复。
- **本地体验**：支持简体中文、繁体中文和英文界面，可在“设置 → 通用 → 语言”中切换并立即生效，默认跟随系统语言，无匹配语言时使用英文；保存上次处理设置，启用 App Sandbox；不联网、不采集图片内容或路径。

## 使用方法

1. 添加图片或文件夹，也可以直接将文件从 Finder 拖入窗口。
2. 选择尺寸模式，按需启用裁剪并设置比例与位置。
3. 设置输出格式、品质、目录和文件名模板。
4. 开始批处理，在窗口中查看进度和失败情况。

默认命名模板为 `{name}_{width}x{height}_{index}`，例如 `photo_2048x1536_001.jpg`。支持的变量如下，扩展名会自动补齐：

| 变量 | 含义 |
| --- | --- |
| `{name}` | 原文件名，不含扩展名 |
| `{width}` | 输出宽度（像素） |
| `{height}` | 输出高度（像素） |
| `{index}` | 批次序号，至少三位 |
| `{ext}` | 输出格式扩展名 |

取消批处理会清理本轮已生成的文件。应用异常退出后，下次启动时可选择清理或保留未完成批次生成的文件。

## 开发环境

- macOS 15 或更高版本。
- Xcode 26 或更高版本，Swift 6。
- Apple Silicon 或 Intel Mac；仓库内的 libwebp XCFramework 包含 arm64 与 x86_64 架构。

## 构建与测试

克隆仓库并打开工程：

```shell
git clone https://github.com/KOPElan/pixshift.git
cd pixshift
open PicTool.xcodeproj
```

在 Xcode 中选择 `PicTool` scheme 与 `My Mac` 运行目标，然后运行应用。产品名称为 PixShift，工程、scheme 和源码目录仍使用 `PicTool`。需要签名运行时，请在 Signing & Capabilities 中选择自己的开发团队。

命令行构建（跳过代码签名）：

```shell
xcodebuild \
  -project PicTool.xcodeproj \
  -scheme PicTool \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pixshift-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行自动化测试：

```shell
xcodebuild \
  -project PicTool.xcodeproj \
  -scheme PicTool \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pixshift-derived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

历史验证记录包括 arm64 Debug 测试、x86_64 Release 编译和 41 个自动化测试，覆盖尺寸计算、裁剪、格式导出、命名、导入扫描、目录写入预检、运行台账、并发与取消。详见[开发状态](docs/07-development-status.md)。

## 项目结构

```text
PicTool/               应用源码
  App/                 主窗口与设置
  Features/            图片导入、队列、批处理配置与裁剪界面
  Models/              尺寸、格式和裁剪数据模型
  Processing/          图片处理、并发调度与运行台账
  Resources/           应用图标与本地化资源
  Support/             WebP 编码、命名模板与目录写入预检
PicToolTests/          XCTest 单元与集成测试
PicTool.xcodeproj/     Xcode 工程
ThirdParty/libwebp/    WebP 静态 XCFramework 与第三方许可
docs/                 产品、技术与交付文档
```

## 第三方依赖

WebP 编码使用随仓库提供的 **libwebp v1.6.0** 静态 XCFramework，无需额外下载依赖。版本、构建方式和校验值见 [libwebp 说明](ThirdParty/libwebp/README.md)，第三方许可见 [LICENSE](ThirdParty/libwebp/LICENSE)。

## 当前限制

- 文件夹导入不递归扫描子目录。
- 不提供输出效果实时预览；裁剪编辑器提供定位预览。
- 取消会等待正在编码的单张图片到达安全点后再清理。
- 千张图片压力测试、完整 ICC/WebP 元数据验证和发布签名、公证仍待完成。

## 文档索引

- [产品需求文档](docs/01-product-requirements.md)
- [交互与界面规格](docs/02-ux-specification.md)
- [技术设计](docs/03-technical-design.md)
- [隐私与 Mac App Store 准备](docs/04-privacy-and-app-store.md)
- [开发计划与验收](docs/05-delivery-plan.md)
- [实施计划](docs/06-implementation-plan.md)
- [开发状态](docs/07-development-status.md)
