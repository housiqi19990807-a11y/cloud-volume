# Agent Note: Windows bridge 构建与 metadata chunk 目录同步

Status: implemented

## Problem

Windows 云机的正典 bridge 构建被 `winfsp_fs_windows.go` 的未使用 import 阻断；独立的 `make bridge-windows` 还把 `WINFSP_INC := ...` 写进 recipe，使随后传给 cgo 的 `CPATH` 为空。即使绕过构建，Cloud Files 文件写入也会在 chunk 文件 fsync、原子改名之后因只读目录句柄调用 `FlushFileBuffers` 返回 `ERROR_ACCESS_DENIED`，从而在 journal admission 前失败，任务队列没有可执行的写入项。另一个 Windows 特有竞态是 metadata stage 用默认 `os.Open` 长时间读取 sync-root 文件，它不共享 delete access，Explorer 的紧随写入重命名会报 `ERROR_SHARING_VIOLATION`；只放开 delete share 又会让 completion callback 抢先把不存在的旧 Desired 路径重命名。真实回归还暴露普通 NTFS 文件只会产生 fsnotify `Rename(old)+Create(new)`（或 `Remove(old)+Create(new)`），CFAPI 不保证对其发送 provider rename completion，metadata 挂载会丢掉 Desired rename。

## Decision

Windows bridge 删除未使用 import，`Makefile` 在 Make 变量域声明 vendored WinFsp include 路径。metadata 的目录同步按平台拆分：非 Windows 保持目录 `os.File.Sync`；Windows 用 `CreateFile` 的 `GENERIC_WRITE`、共享读写删除和 `FILE_FLAG_BACKUP_SEMANTICS` 打开目录，再调用 `FlushFileBuffers`。`metadata_write_source_windows.go` 用同样保留普通/UNC 长路径语义的 `CreateFile(GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE)` 取得 source handle，非 Windows 保持 `os.Open`；`stageMetadataWrite` 在打开、`Stat` 和 `Service.WritePath` 全程持有 `writebackMu`。于是 Explorer 可先物理移动已打开文件，而 rename completion 只能在对应旧路径写入已经持久 journal 后运行。chunk 文件 fsync、原子 rename、保护 manifest 与 bbolt 引用提交的既有顺序不变。

metadata 挂载的普通文件改名由 watcher 配对 fsnotify 源/目标事件：源事件把最近一次稳定 size/mtime 指纹保留为 pending rename，随后的 Create 仅在同目录、唯一匹配指纹时折叠为 `enqueueRenamePath` 的持久 rename journal；同目录指纹不唯一时保持创建语义，避免猜错源。`Remove(old)` 事件不再丢弃 pending rename；CFAPI completion callback 与 watcher 路径共用锁和短期 handled 标记，同一 Desired rename 只 journal 一次。legacy（无 metadata write path）挂载不启用配对，保留旧的上传取消 + 新文件入队行为。

## Alternatives considered

- **继续使用只读 `os.File.Sync`** — Windows 会稳定返回 access denied，任何 Cloud Files 文件写入都不能进入持久 journal。
- **吞掉 access denied 或把 Windows 目录同步改为 no-op** — 虽能让入队继续，却悄悄放弃 rename 后、bbolt 提交前的目录持久化屏障，也会掩盖真实缓存 ACL 错误。
- **仅以 `MOVEFILE_WRITE_THROUGH` 替换 rename** — 它不能覆盖保护 manifest 的原子替换，且不是两个目录同步点的直接语义替代；可写目录句柄已能在目标 Windows 环境完成真正 flush。
- **继续用默认 `os.Open` 读取 stage 源** — Go 的 Windows 默认分享模式没有 `FILE_SHARE_DELETE`，Explorer 的移动会稳定遇到共享冲突。
- **只放开 delete share、但在打开后才取得 `writebackMu`** — physical move 可以先完成，completion callback 会抢先 journal 化 rename，随后写入再尝试旧路径会丢失 Desired 变更；锁必须从打开延续到 admission。
- **对普通文件改名依赖 CFAPI completion callback** — 真实 Windows 枚举证明普通 NTFS 文件常只有 fsnotify Rename/Create（甚至 Remove/Create），provider callback 可能缺席，Desired rename 会完全丢失。
- **仅用路径或大小配对 fsnotify 改名** — 大文件拷贝中同目录多文件会猜错源；唯一目录 + 精确 size/mtime 指纹不匹配时宁可走创建语义。

## Consequences

chunk 和 manifest 父目录仍须对当前用户可写；权限或 flush 错误继续明确阻止 journal admission，避免宣称本地写入已持久化。source handle 在物理 rename 后继续代表原文件内容，只有关闭后才允许 callback 进入后续 metadata mutation；读源路径的 create/stat/admission 同时串行化，不能从中间释放锁。Windows 目录与 source-handle 的回归以专用测试锁定，现行文件与平台契约见 [mount_metadata_core](../../../features/mount_metadata_core.md) 和 [windows_dev](../../../features/windows_dev.md)。

## Testing

Windows 云机实测只读目录句柄的 `FlushFileBuffers` 返回 `ERROR_ACCESS_DENIED (5)`，同一路径的 `GENERIC_WRITE` 句柄成功；读取中的共享-delete source handle 可被 `os.Rename`，且仍可读取原内容。`go test ./go/mount/metadata`、Windows 专用 `TestSyncDirectoryFlushesWindowsDirectory`、`TestOpenMetadataWriteSourceAllowsRenameWhileOpen`、`TestOpenMetadataWriteSourceAllowsDirectoryValidation`、`TestWindowsWatcherPairsNormalFileRenameIntoMetadata`、`TestWindowsRenameSourceRemoveEventKeepsPendingPair`、`TestWindowsWatcherKeepsLegacyRenameAsNewUpload`、长路径规范化测试，以及同工具链的 Windows c-shared bridge / `scripts/run_windows.ps1 -Build` 均覆盖该决定。云机 mock S3 真实回归进一步验证写后立即改名进入唯一 rename 任务并收敛远端。
