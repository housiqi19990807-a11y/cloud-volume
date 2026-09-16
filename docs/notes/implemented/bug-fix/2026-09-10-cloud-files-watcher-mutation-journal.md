# Agent Note: Cloud Files watcher 删除与改名 journal

Status: implemented

## Problem

普通 NTFS 文件在 Cloud Files sync root 内删除时，CfAPI 不保证发送 delete completion callback；只消费 fsnotify `Remove` 又只会取消本地待上传状态，已确认上传的远端对象会残留。与此同时，watcher 在读取 fsnotify 事件的 goroutine 内直接提交 metadata bbolt journal，千级 Explorer 批量改名可阻塞读取并耗尽事件通道。完成改名去重沿用三秒事件忽略 TTL，晚到 callback 有机会重复提交同一 rename。

## Decision

metadata 挂载的非 rename `Remove` 在保留 pending rename 候选后调用 `deletePath`，使已确认的普通本地文件通过 `metadata.Service.DeletePath` 获得持久删除 journal；未确认写入由同一 Desired/journal 语义消除。投影身份独立于待水合标记保留到删除或改名：已水合占位符仍只让 CFAPI completion 提交删除；completion 先到时忽略尾随 fsnotify，fsnotify 先到时等待 completion，两个顺序都只产生一次 admission。Cloud Files callback 与 watcher 将 write、mkdir、delete 和 rename admission 放进会话级 FIFO 后台队列：事件线程对 write 只打开带 delete-share 的源句柄，后续物理 rename 不会使排队读取丢失；父目录 revision 被 metadata worker 并发推进时 rewind 同一句柄并有限重试 stale cursor。提交不等待 bbolt，关闭 watcher 前排空已接收工作，队列 worker 是唯一同步 journal 边界。改名配对与 CFAPI completion 在提交前登记相同的完成标记，成功或排队中的项都不会重复 admission；worker 成功后才 Rebase watcher 状态，普通文件 rename admission 失败则从物理新路径补写 Desired 并删除仍存在的旧路径。完成标记使用独立的一分钟 TTL，配对候选仍保留短事件窗口。

## Alternatives considered

- **只在 CfAPI delete completion 中处理删除** — 普通本地文件没有可靠 callback，正是远端对象残留的根因。
- **为 watcher 队列设固定容量并在满时阻塞** — 慢 journal 会把背压传回 fsnotify 读取，批量改名仍可能溢出内核事件流。
- **每项工作独立 goroutine** — 会避免读取阻塞，却不能保证 delete/rename 的 filesystem 顺序，也会在批量操作时无界并发 bbolt 提交。
- **只把完成去重 TTL 延长为一分钟** — 它不解决 watcher 同步 journal 提交，也无法让普通 `Remove` 生成删除 mutation。

## Consequences

关闭挂载会在释放 metadata handle 前等待已接收的 watcher mutation 落入 journal；极大批量事件的内存占用由未落盘 FIFO 决定，而非 fsnotify 通道容量。journal admission 失败会记录错误并清除 rename 去重标记，供后续事件重新尝试；本地物理视图保持 Explorer 已完成的结果。

## Testing

`TestWindowsWatcherRemoveOfUploadedLocalFileJournalsRemoteDelete` 钉住普通文件删除语义；占位符用例覆盖未水合、水合及 completion/watcher 两种顺序。`TestWindowsWatcherRealFilesystemDeleteReachesRemote` 在本机 NTFS 上经真实 fsnotify CREATE/WRITE/REMOVE、metadata worker 与测试远端验证端到端删除。队列用例在首项阻塞时接收 2,000 项并于关闭时排空；源句柄用例验证排队写跨 rename 可读；watcher-only 与 callback-first 用例强制 rename source 不存在，验证 admission 失败仍从物理 target 补写；真实 fsnotify 批量用例连续改名 128 个唯一指纹文件并检查 Desired 收敛；TTL 用例钉住至少 30 秒。以上回归在 Windows ARM64 CGO 环境执行。
