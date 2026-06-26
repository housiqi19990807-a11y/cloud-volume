// ignore_for_file: library_private_types_in_public_api
part of 'file_sync_profile_editor.dart';

// 分步配置的字段构建方法。作为顶层函数接收 _FileSyncProfileEditorState，
// 这样能访问所有字段和 setState，同时把代码量分到两个文件。

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

/// 步骤 1：配置名称 + 关联账号。
Widget stepBasicInfo({
  required ShadThemeData theme,
  required _FileSyncProfileEditorState self,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      stepLabel(theme, '配置名称'),
      ShadInput(
        controller: self._nameController,
        placeholder: const Text('例如：工作文档同步'),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '关联账号'),
      if (self.widget.profiles.isEmpty)
        Text(
          '暂无已配置账号，请先在账号管理中添加。',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
        )
      else
        ShadSelect<String>(
          initialValue: self._accountProfile,
          placeholder: const Text('选择账号'),
          selectedOptionBuilder: (context, value) => Text(value),
          options: self.widget.profiles
              .map((p) => ShadOption<String>(value: p.name, child: Text(p.name)))
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) self.markDirty(() => self._accountProfile = v);
          },
        ),
      const SizedBox(height: 12),
      Text(
        '选择此同步配置使用的远程存储账号。',
        style: TextStyle(fontSize: 11, color: theme.colorScheme.mutedForeground),
      ),
    ],
  );
}

/// 步骤 2：远端桶名、远端目录前缀、本地目录。
Widget stepSyncTarget({
  required ShadThemeData theme,
  required _FileSyncProfileEditorState self,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      stepLabel(theme, '远端桶名'),
      ShadInput(
        controller: self._bucketController,
        placeholder: const Text('例如：my-bucket'),
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '远端目录前缀（可留空）'),
      ShadInput(
        controller: self._remotePrefixController,
        placeholder: const Text('例如：docs/work'),
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
        ],
      ),
    ],
  );
}

/// 步骤 3：同步方向、冲突策略、同步周期、静默时间、排除规则、启用开关。
Widget stepSyncStrategy({
  required ShadThemeData theme,
  required _FileSyncProfileEditorState self,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      stepLabel(theme, '同步方向'),
      ShadSelect<String>(
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
      const SizedBox(height: 16),
      stepLabel(theme, '冲突策略'),
      ShadSelect<String>(
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
      const SizedBox(height: 16),
      stepLabel(theme, '同步周期'),
      ShadSelect<int>(
        initialValue: self._intervalSeconds,
        selectedOptionBuilder: (context, value) => Text(_intervalLabel(value)),
        options: _intervalOptions
            .map((s) => ShadOption<int>(value: s, child: Text(_intervalLabel(s))))
            .toList(growable: false),
        onChanged: (v) {
          if (v != null) self.markDirty(() => self._intervalSeconds = v);
        },
      ),
      const SizedBox(height: 16),
      stepLabel(theme, '热数据静默时间'),
      ShadSelect<int>(
        initialValue: self._quietSeconds,
        selectedOptionBuilder: (context, value) => Text(_quietLabel(value)),
        options: _quietOptions
            .map((s) => ShadOption<int>(value: s, child: Text(_quietLabel(s))))
            .toList(growable: false),
        onChanged: (v) {
          if (v != null) self.markDirty(() => self._quietSeconds = v);
        },
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
