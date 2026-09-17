# Agent Note: S3 受跟踪整文件上传的签名哈希

Status: implemented

## Problem

小于 multipart 阈值的挂载写回会以带 task ID 的 `PutObject` 发送。进度包装器若只实现 `io.Reader`，SigV4 在计算 payload hash 后无法回绕请求体而上传失败；若只补回 `io.Seeker`，签名预读与实际发送都会累计进度，运行中的任务会显示超过总字节数。

## Decision

普通 `UploadFileContext` 与 resumable 的整文件分支先使用未包装的本地文件计算 SHA-256、回绕文件，再为单次 `PutObject` 注入位于 `ComputePayloadHash` 之前的 Finalize middleware。AWS SDK 在 operation 开始时清除 stack values，因此 middleware 在 operation stack 内设置 SigV4 hash。实际 body 仍使用 `contextReadSeeker`，使传输重试可以回绕，只有请求体发送读取进入任务进度。

## Alternatives considered

**只把 `contextReader` 换成 `contextReadSeeker`。** 这能恢复上传，但 signer 的整文件预读也会调用进度回调，进度在 HTTP 响应前已超过总量。

**直接在调用 context 上调用 `v4.SetPayloadHash`。** SDK 的 `invokeOperation` 会清除调用方的 stack values，payload hash 不会传入 signing middleware，仍会发生预读。

**对所有上传使用 `UNSIGNED-PAYLOAD`。** 这改变了 HTTP 明文与兼容 S3 服务的签名语义，且不必要地放宽了完整性保护。

## Consequences

小文件整对象上传多一次本地顺序读取以计算 SHA-256；该路径最大为 32 MiB，且避免了失败重试与错误进度。multipart 分块路径已有 seekable body，不改变其签名或进度策略。

## Testing

`go/s3/objects_resume_test.go` 在服务端读取完 body 但尚未响应时断言普通和 resumable 整文件上传均为运行中 `N/N`，并校验正文、`X-Amz-Content-Sha256` 与最终完成快照。
