// ignore_for_file: library_private_types_in_public_api
part of 'file_sync_profile_editor.dart';

// 分步配置的字段构建方法。顶层函数接收 _FileSyncProfileEditorState，
// 通过它访问字段和 markDirty。

const _intervalOptions = <int>[60, 120, 300, 600, 1800, 3600];
const _quietOptions = <int>[0, 5, 10, 30, 60, 120];

Widget stepLabel(ShadThemeData theme, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.foreground,
      ),
    ),
  );
}

/// 步骤 1「同步两端」：选本地目录 + 选远端目录（通过文件管理式浏览器）。
/// 配置名称可选，留空用桶名做默认值。
Widget stepPickEndpoints({
  required ShadThemeData theme,
  required _FileSyncProfileEditorState self,
}) {
  final remote = self._remoteDir;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      stepLabel(theme, '配置名称（可选）'),
      ShadInput(
        controller: self._nameController,
        placeholder: const Text('留空则使用桶名'),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '本地目录'),
      Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: self._localPathController,
              placeholder: const Text('点击右侧按钮选择目录'),
              readOnly: true,
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.secondary(
            onPressed: self._pickLocalDirectory,
            child: const Text('选择'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: self._localPathController.text.trim().isEmpty
                ? null
                : self._openLocalDirectoryInShell,
            child: const Text('打开本地目录'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '远端目录'),
      Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: TextEditingController(text: remote == null
                  ? ''
                  : '${remote.bucket}/${remote.prefix.isEmpty ? '' : remote.prefix}'),
              placeholder: const Text('点击右侧按钮选择远端目录'),
              readOnly: true,
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.secondary(
            onPressed: self._pickRemoteDirectory,
            child: const Text('选择'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: self._remoteDir == null
                ? null
                : () => self._openRemoteSyncDirectory(),
            child: const Text('打开同步目录'),
          ),
        ],
      ),
    ],
  );
}



/// 步骤 2「同步策略」：同步方向、冲突策略、同步周期、静默时间、排除规则、启用开关。
Widget stepSyncStrategy({
  required ShadThemeData theme,
  required _FileSyncProfileEditorState self,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      stepLabel(theme, '同步方向'),
      SizedBox(
        width: double.infinity,
        child: ShadSelect<String>(
          initialValue: self._direction.value,
          selectedOptionBuilder: (context, value) =>
              Text(SyncDirection.fromValue(value).label),
          options: SyncDirection.values
              .map((d) => ShadOption<String>(value: d.value, child: Text(d.label)))
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) {
              self.markDirty(() => self._direction = SyncDirection.fromValue(v));
            }
          },
      ),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '冲突策略'),
      SizedBox(
        width: double.infinity,
        child: ShadSelect<String>(
          initialValue: self._conflictPolicy.value,
          selectedOptionBuilder: (context, value) =>
              Text(SyncConflictPolicy.fromValue(value).label),
          options: SyncConflictPolicy.values
              .map((p) => ShadOption<String>(value: p.value, child: Text(p.label)))
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) {
              self.markDirty(() => self._conflictPolicy = SyncConflictPolicy.fromValue(v));
            }
          },
      ),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '同步周期'),
      SizedBox(
        width: double.infinity,
        child: ShadSelect<int>(
          initialValue: self._intervalSeconds,
          selectedOptionBuilder: (context, value) => Text(_intervalLabel(value)),
          options: _intervalOptions
              .map((s) => ShadOption<int>(value: s, child: Text(_intervalLabel(s))))
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) self.markDirty(() => self._intervalSeconds = v);
          },
      ),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '热数据静默时间'),
      SizedBox(
        width: double.infinity,
        child: ShadSelect<int>(
          initialValue: self._quietSeconds,
          selectedOptionBuilder: (context, value) => Text(_quietLabel(value)),
          options: _quietOptions
              .map((s) => ShadOption<int>(value: s, child: Text(_quietLabel(s))))
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) self.markDirty(() => self._quietSeconds = v);
          },
      ),
      ),
      const SizedBox(height: 6),
      Text(
        '文件写入后静默该秒数才纳入同步，避免正在编辑的文件频繁上传。',
        style: TextStyle(fontSize: 11, color: theme.colorScheme.mutedForeground),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '排除规则（每行一条）'),
      ShadInput(
        controller: self._excludeController,
        placeholder: const Text('.DS_Store\n*.tmp'),
        maxLines: 4,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(
              '启用此同步配置',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
          ShadSwitch(
            value: self._enabled,
            onChanged: (v) => self.markDirty(() => self._enabled = v),
          ),
        ],
      ),
    ],
  );
}

String _intervalLabel(int seconds) {
  if (seconds >= 3600) return '${seconds ~/ 3600} 小时';
  if (seconds >= 60) return '${seconds ~/ 60} 分钟';
  return '$seconds 秒';
}

String _quietLabel(int seconds) {
  if (seconds == 0) return '0 秒（实时）';
  if (seconds >= 60) return '${seconds ~/ 60} 分钟';
  return '$seconds 秒';
}
