# 云卷 / Cloud Volume

`云卷` 是一个面向 macOS、Windows、Linux 的 Flutter 桌面客户端，用来管理 S3 兼容对象存储，并把对象存储以更接近桌面文件管理器的方式呈现出来。

它不只是一个“桶列表 + 上传下载”工具，还包含本地缓存、可挂载 WebDAV 视图、应用级回收站、分享链接管理、任务队列，以及针对 Finder / Archive Utility 一类桌面工作流做过的本地优先优化。

## 仓库截图

![云卷主界面](docs/screenshots/main-page.png)

## 核心能力

- 文件管理：桶列表、目录浏览、列表/网格视图、右键操作、搜索、多选、批量下载/删除。
- 挂载访问：macOS 通过系统 WebDAV 卷挂载，Linux 通过 FUSE 挂载，Windows 支持 WebDAV 与 Cloud Files 方案，三端都复用本地缓存、overlay 与异步写回链路。
- Windows WebDAV 挂载：把当前桶映射成 Windows WebDAV 网络驱动器，直接出现在 Explorer 的“此电脑”里，并复用现有本地优先读写与任务队列逻辑。
- 本地优先：挂载写入、删除、改名、移动先落本地缓存与 overlay，再异步回写远端。
- 文件管理同步提示：进入已挂载桶时，顶部挂载状态会直接显示 `等待同步 N` / `同步中 N`，便于判断桌面写入是否已经回传远端。
- 文件列表同步状态：进入已挂载桶的文件列表后，会直接包含待同步的本地写回项，并在独立状态列显示 `已同步`、`等待同步` 或 `同步中`；名称下方不再重复放同步文案，目录会按子项聚合同步状态。
- Windows Cloud Files 原生状态：默认的 `Cloud Files + 本地缓存/异步同步` 模式现在会把写回队列状态投影回 Explorer 的 sync root，待同步文件会显示 Cloud Files 的未同步状态，上传完成后恢复为已同步状态。
- 断点续传：大文件挂载上传支持可恢复 multipart writeback，挂载下载支持复用完整缓存与 `.downloading` 分片续传。
- 回收站：应用级软删除、全局回收站 / 桶级回收站、恢复、彻底删除、分页与无限滚动。
- 分享管理：为文件创建预签名下载链接，集中管理分享记录、续期、复制与删除。
- 任务队列：统一展示上传、下载、复制、移动、删除、挂载写回，支持筛选、取消、持久化恢复。
- 桌面体验：托盘图标、透明标题栏、统一中文字体、面向桌面鼠标操作的上下文菜单和固定表头列表。
- Windows 宿主壳：使用与 macOS 一致的 `云卷` 品牌图标，移除系统标题栏，在应用内右上角提供自定义最小化 / 最大化 / 关闭按钮，并常驻系统托盘以支持隐藏和恢复主窗口。
- Linux 宿主壳：去掉 GTK 系统标题栏，使用与 Windows 相同的应用内右上角最小化 / 最大化 / 关闭控件，支持直接拖动自定义顶部区域移动窗口，关闭时会提示“最小化窗口”或“退出云卷”，并按当前屏幕分辨率收敛默认窗体大小。
- Windows 挂载同步：Explorer 内对映射 WebDAV 盘的新建、写入、删除、改名会继续走现有 Go 侧本地缓存、写回、删除和移动队列，不影响 macOS 的 WebDAV 异步链路。

## 界面设计

- 品牌名为 `云卷`，使用统一的侧边栏、列表和弹窗风格。
- 内嵌 `Source Han Sans CN`，减少不同平台的中文显示漂移。
- UI 基于 `shadcn_ui`，避免混用多套桌面/Material 风格控件。
- 主界面围绕“文件管理、任务队列、回收站、分享管理、系统设置”五类核心页面展开。

## 运行方式

### 首次启动

- 应用通过 Go FFI bridge 读取 `~/.remote-storage/config.toml`。
- 如果配置缺失或不完整，会先进入初始化配置页。
- 如果访问密钥、签名或网络配置有误，初始化页会把常见 S3 / 网络错误转换成更友好的中文提示。
- 保存后进入主界面，后续设置页可以再次修改下载目录、显示选项、回收站策略等内容。

### 本地开发

```bash
flutter pub get
go mod tidy
make run
```

`make run` 是本仓库的标准启动方式：

- macOS: 先构建 Go bridge 到 `bin/bridge/libremote_storage_bridge.dylib`，再以正确的 `DEVELOPER_DIR` 启动 Flutter macOS 应用
- Linux: 先构建 Go bridge 到 `bin/bridge/libremote_storage_bridge.so`，并把它随 Linux bundle 一起安装后再启动 Flutter Linux 应用

平台相关命令：

- macOS: `make bridge-macos`, `make run-macos`, `make build-macos`
- Linux: `make bridge-linux`, `make run-linux`, `make build-linux`
- Windows: `make bridge-windows`, `make run-windows`, `make build-windows`

Windows 本地启动前提：

- 需要可用的 Flutter Windows Desktop 环境。
- 需要可用的 MinGW-style C toolchain 供 Go `c-shared` bridge 使用，推荐 `MSYS2 UCRT64` 的 `gcc/g++`。
- 如未把 `flutter` / `gcc` 放进 `PATH`，可以直接运行 `powershell -ExecutionPolicy Bypass -File .\scripts\run_windows.ps1`。

Windows 现在会在 `flutter run -d windows` / `flutter build windows` 期间自动构建 `bin/bridge/remote_storage_bridge.dll`，并把它复制到生成出的 runner 目录，避免构建后 exe 因缺少 bridge 而无法启动。
如果本机配置了 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`，请确保 `NO_PROXY` 包含 `127.0.0.1,localhost`；仓库自带的 `scripts/run_windows.ps1` 会自动补上这两个值，避免 `flutter run` 通过代理去连接本地 Dart VM service 而导致调试连接提前断开。

Linux 本地启动前提：

- 需要可用的 Flutter Linux Desktop 环境。
- 需要 `clang`、`cmake`、`ninja-build`、`pkg-config`、`libgtk-3-dev`、`fuse3` 以及可用的 Go CGO 编译链。
- Linux runner 现在也会在 `flutter run -d linux` / `flutter build linux` 期间自动构建 `bin/bridge/libremote_storage_bridge.so`，并把它安装到 bundle 的 `lib/` 目录，避免打包后的可执行文件因缺少 bridge 而无法启动。
- Linux 挂载现在使用用户态 FUSE mount，把 bucket 暴露到 `~/Cloud Volume/<bucket>`，目录读取、按需下载、本地暂存、延迟写回、删除和改名都继续复用现有 Go 侧本地优先逻辑。

## 配置项

初始化页会保存这些 S3 兼容存储配置：

- `endpoint`：S3 兼容端点地址
- `region`：区域
- `bucket`：默认桶名
- `access_key_id`：访问密钥 ID
- `secret_access_key`：访问密钥 Secret
- `root_prefix`：可选的根前缀
- `use_path_style`：是否启用 path-style URL

其他应用级设置包括：

- 默认下载目录
- 是否隐藏 `.` 开头文件
- 回收站目录名
- 回收站自动清理保留天数
- 主题强调色

## 架构概览

- Flutter：桌面 UI、页面状态、任务展示、配置与交互层
- Go bridge：配置读写、S3 操作、挂载实现、分享链接、回收站、任务快照
- Desktop mount backends：macOS 走系统 WebDAV 卷挂载，Linux 走用户态 FUSE 挂载，Windows 同时保留 Cloud Files 与 WebDAV 映射盘方案
- 本地缓存与 overlay：保证挂载场景下的本地优先可见性与恢复能力

## 发布

推送标签如 `v0.0.1` 后，会触发 GitHub Actions 构建桌面发行版：

- macOS `amd64` / `arm64` / `universal`
- Windows `amd64` / `arm64`
- Linux `amd64` / `arm64`

产物包含各平台对应的 Flutter 桌面壳与 Go bridge。

## 当前状态

这是一个明显偏“桌面工作流优先”的对象存储客户端，而不是简单的 Web 面板移植版。
如果你希望在对象存储上获得更接近 Finder / 资源管理器的体验，这个仓库就是围绕这个目标持续演进的。
## Windows Mount Modes

Windows now keeps three mount modes available side by side so behavior can be compared without reverting code:

- `cloud_files_cached`: uses the native Cloud Files shell, but hydration goes through the existing cached-download, transfer-queue, and async writeback flow used by the mature mount layer.
- `cloud_files_direct`: uses the native Cloud Files shell and reads placeholder data directly from S3 for direct-path testing.
- `webdav`: keeps the mapped-drive fallback that mounts the local WebDAV server into Explorer as a network drive.

The active mode is stored in config as `windows_mount_mode` and can be changed from Settings. Remount the bucket after switching modes.
Cloud Files remounts now allocate a fresh sync-root directory and rebuild the mount session when the same bucket's mount config changes, which helps avoid stale sync-root reuse after an incomplete unmount.
Settings also expose a force-reset mount action that calls `cleanup_mounts` to clear stuck bucket mounts, stale sync roots, and cached mount state before retesting Explorer writes.
The Cloud Files placeholder path now coalesces repeated directory fetch callbacks and skips placeholder creation for entries that already exist locally, which reduces Explorer browse loops and placeholder callback errors on busy folders.
## Runtime Logs

Go bridge runtime logs are written to `~/.remote-storage/runtime/logs/bridge.log`, which now includes Windows Cloud Files fetch-data and placeholder diagnostics for mount failures.

## UI Responsiveness

Flutter now dispatches synchronous Go bridge calls from a background isolate before entering the FFI layer. This keeps bootstrap loading, bucket refreshes, mount-status probes, and object metadata lookups from blocking the desktop UI thread when the bridge is waiting on network or mount work.
