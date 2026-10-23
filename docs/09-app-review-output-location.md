# 2.4.5(i) 输出位置整改

对应 2026 年 10 月 21 日的审核反馈，审核版本为 1.0 (3)。

## 行为变更

- 首次启动默认“统一目录”，输出 URL 为空，不预设 Documents、桌面或原图目录。
- 有图片且处理参数有效时，“开始处理”可点击。统一输出目录为空时，点击后先通过标准 `NSOpenPanel` 让用户选择文件夹，确认后自动继续；取消则回到空闲，不创建输出文件或台账。
- 选择后显示完整输出路径，并通过安全作用域书签记住用户选择。
- “各自原图目录”保留为手动选项；选择后继续按原有逻辑预检权限，必要时使用系统面板补充授权。
- 历史版本的原目录模式没有主动选择标记，因此升级后不自动继承。新版本中用户主动选择的模式会正常记住。已有统一目录书签继续保留。
- 系统面板可能自行恢复最近浏览的位置；面板浏览位置不等于应用已设置输出目录，用户必须点击确认才保存选择。

## 验证结果（2026 年 10 月 23 日）

- 55 项自动化测试通过，覆盖首次无输出目录、历史默认模式迁移、新版本手动模式恢复、无效书签、点击开始自动选目录并继续导出、取消与重试、重复点击不重复弹窗，以及已有目录时不再弹窗。
- Apple Development 签名 Release 构建成功。
- 在 macOS 27.0.1 使用独立测试 Bundle ID 验证首次启动，避免正式应用的已有偏好影响测试。
- 导入图片后，未选择输出目录时“开始处理”可用；界面提示“尚未设置输出文件夹，点击开始处理时会提示选择”。点击后系统面板显示“请选择处理后的图片保存位置”。
- 首次点击开始后取消文件夹选择，目录仍为空，未开始导出；可以再次点击开始重新选择。
- 在启动流程中选择独立输出文件夹后，无需再次点击开始即自动处理，并显示完整路径；导出结果为成功 1 张、失败 0 张，文件生成于选中位置，源目录仅保留原图。
- 更换目录时取消，原有选择保持不变。
- 退出后重启，恢复先前选择的输出目录及完整路径。

## 提交说明

尚未归档、上传或重新提交。下一次提交应使用高于 3 的构建号，并在正式 App Store 分发包中复测上述流程。

上传并验证正式构建后，可使用以下回复：

> Thank you for the clarification. We have updated the export flow so the app no
> longer defaults to the source folder or a preset filesystem location. On first
> launch, no output directory is configured. When users click Start without an
> output folder, the app presents the standard macOS folder selection dialog.
> Confirming a folder automatically continues processing; cancelling the dialog
> does not start an export. The app only remembers a folder explicitly
> selected by the user, and displays its full path. Exporting to each source folder
> remains an optional mode that the user must select manually. We also updated
> migration behavior so the previous source-folder default is not automatically
> retained after updating.
