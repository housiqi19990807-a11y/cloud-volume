# Agent Note: 文件名中段省略统一复用 compactDisplayName

Status: implemented

## Problem

真机复测发现任务/回收站列表的长文件名在结尾被截断，扩展名丢失（`abcdefg.jpg` 显示成 `abc...`），且各文件列表的截断行为不一致：网格卡片走 `compactDisplayName`，任务行是裸 `Text(ellipsis)`，紧凑列表行是 18 字符预算 + 外层尾省略。另外任务行字号（13/11）与文件管理、回收站紧凑行（14/12）不一致。

## Decision

放弃新造截断组件，**统一复用既有 `lib/utils/display_name.dart` 的 `compactDisplayName`**（头 + 尾 + 扩展名，中段 `...`）：

- `FileListTile` 紧凑行（对象/回收站/目录选择器等宽度门表面）：默认 18 字符预算——这些行标题区约 250dp，放得下的名字不许被提前缩短（目录选择器测试锁定该契约）。
- `RemoteTaskRow` 标题：Android 分支传 `maxLength: 14`——任务行右侧动作/徽标挤占后标题区仅 ~110dp，是唯一真正窄的表面；同时把字号对齐移动基线 14/12（`defaultTargetPlatform` 门，桌面维持 13/11 与完整名）。
- 契约正典化进 [mobile_ui.md](../../features/mobile_ui.md) 文件名截断契约与列表行字号基线两行；`display_name.dart` 增加 `maxLength >= 3` assert 防御负区间。

## Alternatives considered

- **像素感知 `FileNameText`（TextPainter 测宽 + 头尾贪心/二分）** — 实现并真机验证过两版（`⋯` 中点方案与 head-tail 方案），最终删除：flex/TextPainter 在不同约束下的组合行为需要反复调试（窄约束 RenderFlex 溢出、fallback 分支在极窄预算下反而丢前后缀），复杂度远超收益；字符预算虽不完美但行为可预测、零测量成本。
- **中点省略号（U+00B7 `·` / U+22EF `⋯`）** — 用户先后否决：`…`/`.` 都落基线与扩展名点混淆；`·` 在思源黑体渲染为间距很大的全角大圆点；`⋯` 可用但方案整体随像素感知组件一起放弃。
- **全表面统一 `maxLength: 14`** — P1 评审否决：宽度门表面（目录选择器等）行宽充裕，提前缩短违反"放得下不截"契约并破坏既有测试；14 只给真正窄的任务行。

## Consequences

- 已知限制（记录于 mobile_ui.md）：预算按 UTF-16 字符数而非显示宽度，纯 CJK 长名在任务行仍可能被外层尾省略截掉扩展名；网格卡片截断此前已存在，行为不变。
- `compactDisplayName` 按 UTF-16 码元切分，emoji 等代理对可能被拦腰切断（预存行为，未在本批处理）。

## Verification

- `test/display_name_test.dart` 6 例：短名直通、头尾+扩展名、无扩展名、极小预算退化、空串/单字符/纯扩展名/超长扩展名极端输入。
- `remote_directory_picker_dialog_test`（放得下不提前缩短契约）16 例、`file_manager_object_browser_mobile_test`、`transfers_page_batch_actions_test`、`remote_task_display_test` 全绿。
- 真机（Xiaomi 13 Pro）验证：对象列表 `9478a939...c67.png` 头尾+扩展名保留；三页文件列表字号一致（用户确认）。
