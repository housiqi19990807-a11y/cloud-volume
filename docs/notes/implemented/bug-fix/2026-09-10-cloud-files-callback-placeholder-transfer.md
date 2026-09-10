# Agent Note: Cloud Files 目录回调传输真实占位符

Status: implemented

## Problem

Cloud Files 的 `FETCH_PLACEHOLDERS` 回调先用 `CfCreatePlaceholders` 在磁盘创建条目，再以 `CfExecute(TRANSFER_PLACEHOLDERS)` 的零数组完成请求。资源管理器因此把当前目录缓存为零项，即使稍后底层目录能看到已创建的条目；嵌套目录继续收到同样的零项回复，文件无法从该列表路径到达。

## Decision

每个 `FETCH_PLACEHOLDERS` 请求都从 metadata 列表取得同一份不可变的直接子项描述符，并以该请求自己的 callback info 调 `CfExecute`。成功的单批传输携带 C heap `CF_PLACEHOLDER_CREATE_INFO[]`、`PlaceholderTotalCount == PlaceholderCount == len(items)`、`STOP_ON_ERROR | DISABLE_ON_DEMAND_POPULATION`；C wrapper 返回 `EntriesProcessed`，Go 同时检查其等于条目数及每条 `Result == STATUS_SUCCESS`，之后才记录本地投影。UTF-16 名称、身份与数组均到同步 `CfExecute` 返回后才释放。短 TTL 与并发等待者缓存/转交描述符而不是零项完成信号，所以每个 callback 都有自己的完整 transfer。

启动投影仍用 `CfCreatePlaceholders`，但 sync root 注册时禁用 root 的按需枚举，避免预创建根目录后对同名条目再走 callback transfer；嵌套目录继续由回调完成首次枚举。

## Alternatives considered

- **继续磁盘预创建后回复零数组** — 这直接违背 CFAPI 对 callback 返回匹配条目的契约，并已在真实资源管理器枚举中复现为空列表。
- **吞掉 callback 或仅关闭按需枚举** — 不会把嵌套目录的远端条目交给资源管理器，且会把短暂错误伪装成完整空目录。
- **使用 Go heap 的数组或缓存原生数组** — cgo 不能安全把含指针的 Go 内存交给 C API，且不同 callback 的 request/transfer key 不能复用一个已完成的 native operation。

## Consequences

完整目录枚举的 native 失败、部分处理和单条创建失败都会显式失败而不写入 projection cache；后续请求可重新获取 metadata，而不会把未创建条目当作已存在。实现与回归锚点见 [Windows Platform](../../../features/windows_platform.md)。

## Testing

Windows 专用 gate/transfer-plan 测试覆盖非空、空、并发和 TTL 描述符传递；云机 C ABI 回归在全新 sync root 上覆盖首次根/嵌套枚举、读取、写回和任务投影。
