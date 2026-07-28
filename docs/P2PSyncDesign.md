# P2P 挂载变更发现设计

目标是在同局域网内的多台设备之间加速变更通知和文件读取，而不是让每台设备都独立回源对象存储。对象存储继续是字节、版本和最终一致性的权威来源；P2P 传递"某路径可能已变"的低敏感事件，并可选地从局域网 peer 读取文件内容以加速读路径。接收端仍要从远端重新列举或 `HEAD` 确认版本。

## 设计原则

- **远端是权威。** P2P 是加速层，不是替代层。所有 P2P 读都携带 version hint，最终以远端 `HeadObject` / `ListObjects` 结果为准。
- **零配对。** 同账号自动发现。两台设备登录同一个存储端点 + Access Key，mDNS 广播的账号指纹匹配后自动建立信任，不需要扫二维码、输配对码。离开局域网 → mDNS 失效，无残留信任状态。
- **不泄露凭证。** 事件体不包含文件内容、Access Key、Secret Key、明文桶名、明文路径。账号指纹用 HMAC(endpoint + AK, 固定盐) 单向计算。

## 推荐分期

1. **P0：远端轮询兜底（已实现）。** 每个挂载会话记录近期读取的目录，45 秒内每 5 秒轮询，之后退避至 30 秒；3 分钟无目录活动后停止轮询。轮询只刷新这些目录的远端列表和缓存，不扫描整个桶，也不会删除本地待写回项。
2. **D1：局域网即时通知（已实现）。** 通过 mDNS 发现 `_cloudvolume._tcp` 服务，用账号指纹（HMAC(endpoint + AK)）匹配同账号设备。**每个已启用 P2P 的账号档案各自注册一条 mDNS 服务**（独立的 QUIC 监听端口），因此多账号环境下只要两台设备共享任意一个账号即可互相发现，与当前活跃档案无关。发现后通过 QUIC 单播签名事件（Ed25519）。事件触发后接收端调用 `RefreshRemoteDirectory` 立即刷新父目录缓存。可在设置页面开关 P2P（开关按账号档案持久化）。
3. **D2：局域网内容直传（进行中）。** B 端读文件时，先查局域网 peer 有无相同版本的完整副本。有则通过 QUIC 分块并行拉取，拉完后校验每块 HMAC 与远端 HEAD 的版本。S3 优先使用 ETag；没有 ETag 的后端使用修改时间 + 文件大小作为兼容回退，因此同秒同尺寸覆盖可能短暂命中旧缓存。该风险与普通缓存路径一致；不扫描完整文件计算 hash。分块大小可在设置页面配置（1-64 MB，默认 4 MB）。
4. **P2：跨网络 P2P（未开始）。** 引入独立信令服务交换短期 WebRTC candidate；默认走 DataChannel，必要时由 TURN 中继事件。需要运营决策。

## 身份与发现（零配对）

- 每台设备首次启动时自动生成并本地保护 Ed25519 设备密钥（`~/.cloud-volume/runtime/p2p-identity.json`，0600 权限）。
- 账号指纹 `HMAC-SHA256(key=SHA256(endpoint + "/" + accessKey), data="cloud-volume-lan-discovery-v1")[:16]`。两台设备有相同 endpoint + AK 即产生相同指纹。
- mDNS 注册 `_cloudvolume._tcp` 服务，TXT 记录包含 `fp=<accountFingerprint>` 和 `dev=<deviceId>`。每个账号指纹一条服务记录，bridge 为每个启用 P2P 的档案维护一个 `PeerManager`（见 `bridge/dispatch_p2p.go` 的 `ensureP2PManagers`），档案增删改后自动对账（创建/替换/停止）。
- 收到其他设备的 mDNS 广播后，各账号的 PeerManager 分别用自己的指纹匹配：匹配 → 自动信任并加入该账号的 peer 集合；不匹配 → 忽略。同一台对端设备可能同时出现在多个账号的 peer 集合里，设置页聚合展示并按账号标注。
- 变更广播按来源账号路由：mount 层 `BroadcastPayload` 与 bridge 层 `broadcastPeerMutation` 都携带发起方配置，bridge 用其指纹找到对应账号的 PeerManager 再发送，避免把 A 账号的事件发给只有 B 账号的设备。
- 传输用 QUIC（TLS 1.3 加密），证书为自签 ECDSA P-256。peer 信任靠 mDNS 指纹匹配，不靠 PKI。

## 事件结构

事件体为 `{deviceId, sequence, accountFingerprint, bucketFingerprint, pathHash, parentHash, versionHint, operation, timestamp, nonce}`，并附 Ed25519 签名。

- `bucketFingerprint` = HMAC(accountFingerprint, bucket)
- `pathHash` = HMAC(accountFingerprint, virtualPath)
- 事件不含文件内容、Access Key、Secret Key、分享链接或完整文件名。
- 接收端收到事件只调用 `RefreshRemoteDirectory`（`fetchDirectory` + `storeList`），与 P0 轮询走同一路径，只是触发方式从定时变为事件驱动。

## 代码结构

### Go 层

- `go/p2p/identity.go` — Ed25519 设备密钥生成/存储/加载 + 账号指纹 / 桶指纹 / 路径 hash 计算。
- `go/p2p/discovery.go` — mDNS 服务注册 + 浏览，`hashicorp/mdns` 库。账号指纹匹配后自动信任。
- `go/p2p/transport.go` — QUIC 监听器 + 连接池 + 长度前缀消息收发。
- `go/p2p/tls_cert.go` — 自签 ECDSA P-256 证书生成。
- `go/p2p/events.go` — `PeerEvent` / `SignedEvent` 结构 + 签名/验签 + JSON 序列化。
- `go/p2p/protocol.go` — 消息类型常量 + 内容传输协议结构（ContentQuery / ContentResponse / ChunkRequest / ChunkResponse）。
- `go/p2p/util.go` — 随机 hex 辅助。
- `go/p2p/manager.go` — `PeerManager` 顶层协调器：发现 + 传输 + 事件路由 + UI 状态查询 + 运行时开关。`BroadcastMutation` 由 mount 层和 bridge 层在远端确认成功后调用。
- `go/mount/peer_refresh.go` — `RefreshRemoteDirectory` 导出函数，P2P 接收事件后调用以即时刷新挂载会话缓存（复用 P0 的 `pollRemoteDirectory`）。
- `go/mount/peer_hook.go` — 原子回调 hook，mount 层不直接导入 p2p 包（避免循环依赖），由 bridge 层注册广播回调。
- `go/mount/writeback_queue.go` — `flushNow` 成功后调用 `PeerBroadcastHook()` 广播 upload 事件。
- `bridge/dispatch_p2p.go` — `get_p2p_status` / `set_p2p_enabled` bridge 方法 + `ensureP2PManagers` 多账号生命周期管理（按档案名维护 PeerManager 表，按指纹路由广播/拉取，状态聚合输出）。

### Flutter 层

- `lib/models/remote_storage_config.dart` — 新增 `p2pEnabled` 和 `p2pChunkSizeMb` 字段。
- `lib/services/remote_storage_gateway.dart` — 新增 `getP2PStatus()` 和 `setP2PEnabled()` 抽象方法。
- `lib/services/remote_storage_api_desktop.dart` — desktop 实现，通过 `runBridgeCall` 调 bridge。
- `lib/widgets/settings_p2p_section.dart` — 设置页面 P2P 区：开关、分块大小选择、已发现设备列表（5 秒轮询）。
- `lib/pages/settings_page.dart` / `settings_page_sections.dart` / `settings_page_layout.dart` — 在"网络"组新增"局域网同步"标签页。

## 冲突与可靠性

- 每设备 sequence 去重，事件 TTL 5 分钟。
- P2P 不保证交付，因此 P0 轮询始终保留。
- 本地待写回与远端事件冲突时保留本地写回队列，先 `HEAD` 比较远端版本；绝不静默覆盖。
- 内容直传只做读加速，不做写传播。B 端从 A 拉到的文件只进 B 的本地读 cache，不会变成 B→远端的级联上传。
- 内容直传校验失败（HMAC 不匹配 / 版本过期）自动丢弃，回退远端对象存储。

## 配置

- `p2pEnabled`（默认 `true`）— 是否参与局域网 P2P 发现和事件同步。
- `p2pChunkSizeMb`（默认 `4`，范围 1-64）— 内容直传的分块大小。较大的分块提高吞吐量，较小降低内存占用。
- 两个配置都在设置页面 → "局域网同步" 标签页可调。

## 落地边界

P0 已将活动目录刷新收敛在 `go/mount/remote_poller.go`，D1 复用相同的缓存刷新路径（`pollRemoteDirectory`）通过 `RefreshRemoteDirectory` 触发。D1 在 App 启动加载配置后通过 `go initP2PFromBootstrap` 异步启动 PeerManager。远端对象存储始终是权威，P2P 事件只触发远端列表刷新，不替代远端读。
