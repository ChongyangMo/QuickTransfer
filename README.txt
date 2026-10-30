快传源码
Windows：0.2.1；Mac / iPhone：0.1.0

Mac、iPhone、Windows 原生局域网照片与文字互传。
Mac / iPhone：SwiftUI、AppKit / UIKit；Windows：C# / WPF。
共用 Rust 静态库或 DLL，使用 LocalSend v2.2 HTTPS / 双向证书协议。

使用
1. 设备接入同一局域网，并打开快传。
2. Windows 在顶部下拉框选择设备，通过“文件”菜单选择或粘贴照片、文件，点击发送。
   文字入口位于“文字”菜单，默认不占主界面，关闭编辑窗口仍保留草稿。
   Mac / iPhone 选择设备后直接输入、粘贴或选择内容发送。
3. 陌生设备首次接收需要确认；勾选“记住此设备”后可自动接收。
4. iPhone 可从照片、Safari 等 App 的系统分享菜单选择“快传”。
   首次可能要在分享菜单“更多”中找到快传，发送完成后会自动返回。
5. 手机接收与大文件发送期间，请保持 App 或分享扩展在前台。
6. Mac 快捷键 Option + Shift + S；Windows 快捷键 Ctrl + Alt + S：调出并填入剪贴板。
7. 找不到设备时可用“+”输入对方 IP 和端口，默认 53317。
8. 如果同一台电脑上的 LocalSend 已占用 53317，可修改快传设置中的端口。
   Windows 保存后自动重启接收服务，正在传输时不允许修改。
9. 文件保留原始内容，不做图像压缩。iPhone 收到照片后可预览，或通过分享存储到照片。
   Windows 主界面采用图片瀑布流，最新内容在左上角，点击查看完整图片。
   图片缩小约三分之一并显示圆角，按每次传输批次显示时间分隔。
   “显示”菜单可关闭“按时间分组”，切换为连续图片流；显示方式会自动记住。
   收到文字时单独弹窗，可选择或复制，不混入图片流。
10. 待发送和传输记录中的图片直接显示缩略图，点击可放大预览。
    Windows 支持 HEIC / HEIF 缩略图和内置预览，使用系统图片解码器。
    Windows 支持粘贴剪贴板图片、文件和文字；文件卡片和图片预览支持拖到桌面或其他应用。
    Windows 新版拖出仍需要实际操作验收。
11. Windows 支持 Ctrl + O 选文件、Ctrl + V 粘贴、Ctrl + Enter 发送。
    关闭窗口后保留托盘服务，右键托盘可退出。
12. Windows 点击“多选”或图片右上角勾选，可跨时间分组选择图片和文件。
    支持 Ctrl + 单击增减选择、Shift + 单击连续选择、Ctrl + A 全选、Ctrl + C 复制、Esc 结束多选。
    多选后可批量复制、拖出；点击“添加”放入待发送列表，再选择设备发送。
    点击“取消多选”退出选择；全选后可点击“取消全选”清空勾选并保留多选模式。

当前范围
- 加密照片、文件、文字互传，LocalSend v2 上传 API 与消息预览兼容。
- 自动发现使用 LocalSend UDP；苹果端另用 Bonjour，Windows 也发布 Bonjour 服务。
- 文件夹、LocalSend 网页分享、PIN 输入界面、断点续传、后台剪贴板自动同步未实现。
- iPhone 后台会暂停接收服务；此版本不承诺锁屏后持续收发。
- 收到的文字由用户主动复制，不自动覆盖剪贴板。

工程
Mac 开发目录：/Users/chongyang/Mac_Project/QuickTransfer
Xcode 工程：QuickTransfer.xcodeproj
core/：C ABI、传输任务、文件保存、设备信息。
apple/Shared/：原生界面、状态、Bonjour、导入与剪贴板。
apple/Mac/、apple/iOS/、apple/Share/：平台入口和分享扩展。
windows/：WPF 界面、DNS-SD、托盘和 Rust DLL 接口。
QuickTransfer.slnx：Windows 解决方案。
windows/Themes/：复用 AntoCopy 的通用控件和配色，跟随系统深浅色。
windows/ViewModels/、Services/、Controls/、Views/：状态、后台服务、文件卡片和窗口。

构建
Rust 1.99.1；Mac 使用现有 Xcode，Windows 使用 .NET 10 SDK 和 Rust MSVC 工具链。
Windows 工具路径在 windows/build.json 中配置，不使用环境变量作为应用配置。
Mac：/usr/bin/python3 scripts/build.py mac --configuration Release
iPhone：使用 Xcode QuickTransferiOS scheme，或在 Mac 桌面会话运行 scripts/build.py ios --configuration Release。
如通过 SSH 构建 iPhone，签名需要 Mac 桌面钥匙串会话；scripts/desktop_build.py --release 可启动一次性构建任务。
Windows：powershell -File windows/build.ps1
生成 build/windows/x64/Release/QuickTransfer.exe，自带 .NET 运行时，不需要安装 Windows App SDK。
仅重编译界面：powershell -File windows/build.ps1 -SkipCore。
旧界面和旧构建保留在 build/archive/；当前前端工程不再使用 WinUI 3。
源码包不含依赖下载缓存，首次构建需要下载 Cargo 与 NuGet 依赖。

配置与文件
Mac：用户 Library/Application Support/QuickTransfer。
iPhone：App Group 内 Library/Application Support/QuickTransfer。
Windows：当前用户本地应用数据目录下 QuickTransfer。
settings.json 为界面配置，identity.json 为本机私钥及证书，trusted.json 为用户记住的证书。
请勿把 identity.json 放入源码仓库或分发给其他设备。

迁移前的协议验证
- iPhone 17 Pro Max 真机与 Mac：照片、文字双向成功，照片 SHA-256 一致。
- Windows 与 Mac、iPhone：照片、文字双向成功，照片 SHA-256 一致。
- iPhone 系统分享扩展：真实图片选择设备发送并自动返回，通过真机 UI 检查。
- 官方 LocalSend CLI 1.18.2：接收本客户端发出的真实照片与文字成功。
- 使用已有真实 PNG 图片和实际源码文字传输，没有预置模拟设备或业务记录。

WPF 0.2.1 的本机检查和待验收项目见 当前进度.txt。

开发用 --verify-config 只在明确传入检查配置时启用；苹果 Release 版本不编译该检查逻辑。
apple/ShareHost 和 apple/Tests 仅用于真机分享检查，不属于交付的手机 App。

