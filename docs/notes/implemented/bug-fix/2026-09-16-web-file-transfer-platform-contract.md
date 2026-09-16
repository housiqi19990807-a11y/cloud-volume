# Agent Note: Web 文件传输服务保持跨平台方法面

Status: implemented

## Problem

`FileTransferClipboardRegion` 同时服务桌面和 Web，并通过条件导入选择文件传输实现。共享层调用了 `localFilePathsFromDrop`,但 Web fallback 没有声明该方法，导致 Web 产物与带内嵌 Web 的 full CLI 在发布构建时无法编译。

## Decision

Web fallback 现在声明与 IO 实现相同签名的 `localFilePathsFromDrop`，并返回空路径列表。浏览器不能安全地把拖放文件转换为宿主机本地路径，因此 Web 仍不处理原生本地路径；浏览器文件选择器上传流程保持原样。IO 实现的拖放解析和桌面剪贴板行为不变。

## Alternatives considered

**在共享 widget 中用 Web 平台判断绕过调用。** 该方案仍让条件导入的两个实现拥有漂移的方法面，后续任意共享调用都可能再次把错误推迟到 Web 构建；它也把平台能力差异泄漏到呈现层。

**为 Web 另拆一套 `FileTransferClipboardRegion`。** 这会重复快捷键、DropRegion 和可写目录门控逻辑，只为隐藏一个本来就应该由服务 fallback 吸收的无操作平台能力，增加桌面/Web 行为漂移风险。

## Consequences

Web 与 native 实现的公共方法面保持一致，发布构建可以静态检查共享调用；Web 拖放/剪贴板本地路径仍明确为空，实际浏览器上传不受影响。新增方法需要引入 `super_drag_and_drop` 类型，但该依赖已经由共享拖放 widget 使用。

## Testing

修复后通过 `flutter build web --release --dart-define APP_VERSION_LABEL=1.2.6 --wasm-dry-run --pwa-strategy=none` 与 `scripts/build_cli_packages.sh --goos linux --goarch amd64 --variant full --version 1.2.6 --output-dir /tmp/cloud-volume-ci-cli`。Wasm dry-run 输出的 `dart:ffi` incompatibility 是既有提示，命令最终成功。
