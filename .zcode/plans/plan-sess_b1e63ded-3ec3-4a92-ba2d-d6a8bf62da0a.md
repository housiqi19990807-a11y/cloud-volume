# 修复：界面删除/重命名等 mutation 后挂载点缓存不同步

## 根因

文件管理界面通过 bridge 方法（`delete_object` / `rename_object` / `move_object` / `copy_object` / `create_directory` / `upload_file` / `upload_directory`）直接走 `storageops.ForConfig(...).XxxObject(...)` 修改远端，**完全没有通知 `go/mount` 的 `bucketCache`**。

而列表加载（`list_object_page`）在非 WebDAV 且挂载活跃时会优先走 `bucketmount.ListMountedObjectPage`，从挂载 session 的 `bucketCache` 读缓存列表。由于外部 mutation 没有失效该缓存，导致：

1. **界面"删除中"卡住**：`_reloadObjectsAfterBucketMutation(forceRefresh:true)` 虽然调了 `InvalidateListCacheForPrefix`，但 `mergeLocalFiles` 仍会用过期的 `localEntries` 把幽灵文件重新塞回列表 → `visibleKeys.contains(key)` 为 true → `_deletingObjectKeys` 不被清。
2. **挂载点（Finder/WebDAV）仍显示文件**：`listDirectory` 命中 `listCache` / `localEntries`，TTL 到期前一直返回幽灵文件。

唯一已经接通的是 `InvalidateListCacheForPrefix`（只清 `listCache`），但它**不清** `objectCache` / `localFiles` / `localEntries` / `deletedPaths`，不足以让界面/挂载点反映外部变更。

## 修复方案（全部 mutation 统一）

在 `go/mount` 新增一组外部失效 API，复刻 `InvalidateListCacheForPrefix` 的范式（导出函数 → manager 查 session → `bucketAccess` 导出方法 → `bucketCache` 私有方法），但扩展到完整语义（按 mutation 类型同时清 listCache / objectCache / localEntries / localFiles，必要时放 tombstone）。然后在 bridge 各 mutation 成功后调用对应失效函数。

### 1. 新增 `go/mount/external_invalidation.go`（新文件，< 500 行）

文件级注释说明：外部（bridge / webapi）绕过 mount 直接改远端时，由此处负责把对应 session 的 bucketCache 同步失效。

导出 API：

```go
// NotifyExternalDelete 标记某路径已被外部（非挂载点）删除。
func NotifyExternalDelete(cfg, bucket, virtualPath string, isDir bool)

// NotifyExternalUpload 标记某路径已被外部上传/覆盖（新对象出现在父目录）。
func NotifyExternalUpload(cfg, bucket, virtualPath string, isDir bool)

// NotifyExternalRename 旧路径删除 + 新路径出现。
func NotifyExternalRename(cfg, bucket, oldPath, newPath string, isDir bool)
```

每个导出函数委托 `globalManager.notifyExternalMutation(cfg, bucket, callback)`，callback 签名为 `func(access *bucketAccess)`，在锁内拿到 access 后执行具体失效。这样三段匹配逻辑（normalizeBucketName / mountSessionMatches / session.access nil 检查）只写一次。

### 2. 在 `go/mount/bucket_access_reads.go` 补 `bucketAccess` 导出方法（接近文件尾，现 < 230 行）

复用已有私有方法组合：

- `MarkExternalDelete(virtualPath string, isDir bool)` → `a.cache.markDeleted(virtualPath, isDir)` + `a.cache.invalidatePath(virtualPath)`
  - `markDeleted` 已做 `removeLocalPathLocked` + 写 tombstone + `invalidateParentsLocked`；补 `invalidatePath` 清 objectCache 和子前缀 listCache。
- `InvalidateExternalUpload(virtualPath string, isDir bool)` → `a.cache.removeLocalPath(virtualPath, isDir)`（清可能残留的本地 staging / localEntries / deletedPaths tombstone，避免幽灵或漏显）+ `a.cache.invalidatePath(virtualPath)` + 父目录 `invalidatePath`。
  - 不放 tombstone（因为是新增/覆盖，不是删除）。
- `InvalidateExternalRename(oldPath, newPath string, isDir bool)` → `MarkExternalDelete(oldPath, isDir)` + `InvalidateExternalUpload(newPath, isDir)`。

### 3. bridge 层接入（`bridge/dispatch.go`、`bridge/dispatch_object_transfer.go`）

在每个 mutation 函数成功分支调用对应失效函数。session 不存在/不匹配时导出函数是 no-op，所以无挂载场景零开销。

- `deleteObject`（dispatch.go:275）成功后：`bucketmount.NotifyExternalDelete(input.Config, input.Bucket, input.Key, input.IsDirectory)`
- `renameObject`（dispatch.go:292）：新路径 = `joinVirtualPath(parent(input.Key), input.NewName)`；`NotifyExternalRename(cfg, bucket, input.Key, newPath, input.IsDirectory)`
- `uploadFile` / `uploadDirectory`（dispatch.go:309/326）：`NotifyExternalUpload(cfg, bucket, input.Key, isDir=false/true)`
  - 注意 `uploadDirectory` 当前是 `go func()` 异步，在 goroutine 完成回调里失效不可靠；先在启动时对 `input.Key` 做 `NotifyExternalUpload`（父目录失效，让用户刷新能看到目录出现），目录内部内容本就渐进上传、靠 TTL/手动刷新。
- `createDirectory`（dispatch.go:259）：新目录 = `joinVirtualPath(input.Prefix, input.Name)`；`NotifyExternalUpload(cfg, bucket, newDir, isDir=true)`
- `copyObject` / `moveObject`（dispatch_object_transfer.go）：
  - copy：`NotifyExternalUpload(cfg, bucket, input.TargetKey, input.IsDirectory)`
  - move：`NotifyExternalRename(cfg, bucket, input.SourceKey, input.TargetKey, input.IsDirectory)`
  - 需要在 `dispatch_object_transfer.go` 补 `import bucketmount "remote-storage/go/mount"`（当前未导入）。

`downloadFile` 不改远端对象视图，跳过。

### 4. webapi 层（`go/webapi/invoke.go`）

webapi 是独立的 HTTP 服务入口，与 bridge 并存。`delete_object` 等分支同样不失效挂载缓存。为保持一致性，同样接入：

- 在 `invoke.go` 顶部导入 `bucketmount "remote-storage/go/mount"`（如未导入）。
- 对 `delete_object` / `rename_object` / `copy_object` / `move_object` / `create_directory` 成功分支调用同样的 `NotifyExternal*` 函数。
- 上传/下载在 webapi 里是否也走同一入口待确认；若 webapi 不涉及上传/下载走 mount 缓存的路径则可只接入前 5 个 mutation。

（如 webapi 当前实际未被桌面端使用、仅作备用 HTTP 接口，可标注此点但为正确性仍接入。）

### 5. Dart 侧

**无需改动 UI 逻辑**。根因解决后：
- `deleteObject` bridge 成功后已失效挂载缓存 → 下次 `list_object_page(forceRefresh:true)` 重新 `fetchDirectory` → 幽灵文件不再出现 → `_deletingObjectKeys.removeWhere` 正常清掉"删除中"标记。
- 挂载点 `listDirectory` 同样失效，Finder/WebDAV 刷新后幽灵消失。

### 6. 测试与验证

- `go test ./...`：现有测试应全绿。
- 新增 `go/mount/external_invalidation_test.go`：
  - 构造 manager + 假 session（或复用现有测试 fixtures），验证 `NotifyExternalDelete` 后 `listDirectory` 不再返回该路径、`localEntries` 被清。
  - 验证 session 不匹配时为 no-op（不 panic）。
- `flutter analyze`：应无新告警（Dart 无改动或仅极小改动）。
- 不做本地 smoke 测试，hand off 给用户复现验证：挂载 → 写文件 → 界面删除 → 界面与挂载点均立即消失。

### 7. 文档更新

- `CHANGELOG.md` `## Unreleased` 加一条：修复界面删除/重命名/移动/复制/建目录/上传后挂载点缓存不同步导致幽灵文件残留的问题；bridge 与 webapi 的外部 mutation 现在会同步失效挂载 session 的 bucketCache。
- `AGENTS.md` Code Map 更新 Feature: File Sync / Feature: Transfer Queue 附近，新增一个简短说明：bridge/webapi 的所有远端 mutation 在成功后会调用 `bucketmount.NotifyExternal*` 同步挂载缓存，避免文件管理与挂载点视图分裂。
- `README.md`：若该 bug 曾被列为已知问题则移除；否则无需改 README（属内部修复）。

## 受影响文件清单

| 文件 | 改动 |
|---|---|
| `go/mount/external_invalidation.go` | **新增**：导出 API + manager 调度 |
| `go/mount/external_invalidation_test.go` | **新增**：覆盖 delete/upload/rename + no-op |
| `go/mount/bucket_access_reads.go` | 追加 `MarkExternalDelete` / `InvalidateExternalUpload` / `InvalidateExternalRename` 3 个导出方法 |
| `bridge/dispatch.go` | delete/rename/createDirectory/uploadFile/uploadDirectory 成功分支调 `NotifyExternal*` |
| `bridge/dispatch_object_transfer.go` | 补 import + copy/move 成功分支调 `NotifyExternal*` |
| `go/webapi/invoke.go` | 同步接入 delete/rename/copy/move/createDirectory |
| `CHANGELOG.md` | Unreleased 条目 |
| `AGENTS.md` | Code Map 条目更新 |

所有新文件 < 500 行，符合 `lib`/`go`/`bridge` 结构规则；每个新文件带文件级注释。