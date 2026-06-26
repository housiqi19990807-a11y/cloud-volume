// 文件同步配置编辑弹窗：分两步完成配置，降低单屏信息密度。
// 步骤 1 选择桶（桶列表来自文件管理的同一数据源，自动绑定关联账号）
// 步骤 2 同步设置（远端前缀、本地目录、同步方向与策略）。
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'file_sync_profile_editor_steps.dart';

class FileSyncProfileEditor extends StatefulWidget {
  const FileSyncProfileEditor({
    super.key,
    required this.buckets,
    required this.onSave,
    this.initial,
  });

  /// 文件管理页加载的桶列表，供用户直接选择目标桶。
  final List<FileManagerBucketEntry> buckets;
  final Future<bool> Function(SyncProfile profile) onSave;
  final SyncProfile? initial;

  @override
  State<FileSyncProfileEditor> createState() => _FileSyncProfileEditorState();
}

class _FileSyncProfileEditorState extends State<FileSyncProfileEditor> {
  final _nameController = TextEditingController();
  final _remotePrefixController = TextEditingController();
  final _localPathController = TextEditingController();
  final _excludeController = TextEditingController();

  // 当前步骤索引（0 = 选择桶，1 = 同步设置）。
  int _step = 0;
  FileManagerBucketEntry? _selectedBucket;
  SyncDirection _direction = SyncDirection.twoway;
  SyncConflictPolicy _conflictPolicy = SyncConflictPolicy.newest;
  int _intervalSeconds = 300;
  int _quietSeconds = 10;
  bool _enabled = true;
  bool _saving = false;
  String? _errorText;

  static const _stepLabels = ['同步两端', '同步策略'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _nameController.text = initial.name;
    _remotePrefixController.text = initial.remotePrefix;
    _localPathController.text = initial.localPath;
    _direction = initial.direction;
    _conflictPolicy = initial.conflictPolicy;
    _intervalSeconds = initial.intervalSeconds;
    _quietSeconds = initial.quietSeconds;
    _excludeController.text = initial.excludePatterns.join('\n');
    _enabled = initial.enabled;
    // 编辑时回填已选桶。
    _selectedBucket = widget.buckets
        .where((b) =>
            b.bucket.name == initial.bucket &&
            b.profileName == initial.accountProfile)
        .firstOrNull;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _remotePrefixController.dispose();
    _localPathController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  /// 供 steps 顶层函数触发重建。
  void markDirty(VoidCallback fn) => setState(fn);

  // 步骤校验：第一步必须选桶，第二步必须选本地目录。
  bool _validateCurrentStep() {
    setState(() => _errorText = null);
    switch (_step) {
      case 0:
        if (_localPathController.text.trim().isEmpty) {
          setState(() => _errorText = '请选择本地目录');
          return false;
        }
        if (_selectedBucket == null) {
          setState(() => _errorText = '请选择一个存储桶');
          return false;
        }
    }
    return true;
  }

  void _next() {
    if (!_validateCurrentStep()) return;
    if (_step < 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    setState(() {
      _errorText = null;
      if (_step > 0) _step--;
    });
  }

  Future<void> _pickLocalDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择需要同步的本地目录',
    );
    if (path != null) {
      setState(() => _localPathController.text = path);
    }
  }

  Future<void> _submit() async {
    final bucket = _selectedBucket!;
    // 名称留空时用「桶名/前缀」或桶名做默认值。
    final name = _nameController.text.trim().isEmpty
        ? (bucket.bucket.name)
        : _nameController.text.trim();
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final profile = (widget.initial ?? SyncProfile(
      id: '',
      name: '',
      accountProfile: '',
      bucket: '',
      remotePrefix: '',
      localPath: '',
      direction: SyncDirection.twoway,
      intervalSeconds: 300,
      conflictPolicy: SyncConflictPolicy.newest,
      excludePatterns: const <String>[],
      quietSeconds: 10,
      enabled: true,
    )).copyWith(
      name: name,
      // 从选中的桶条目自动绑定关联账号。
      accountProfile: bucket.profileName,
      bucket: bucket.bucket.name,
      remotePrefix: _remotePrefixController.text.trim(),
      localPath: _localPathController.text.trim(),
      direction: _direction,
      intervalSeconds: _intervalSeconds,
      conflictPolicy: _conflictPolicy,
      quietSeconds: _quietSeconds,
      excludePatterns: _excludeController.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
      enabled: _enabled,
    );
    final ok = await widget.onSave(profile);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _errorText = '保存失败，请检查配置';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: Text(widget.initial == null ? '新建同步配置' : '编辑同步配置'),
      description: const Text('将一个本地目录与远端桶目录保持同步。'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepIndicator(theme),
            const SizedBox(height: 20),
            // 步骤内容区：可滚动，防止字段过多时溢出。
            Flexible(
              child: SingleChildScrollView(
                child: switch (_step) {
                  0 => stepPickEndpoints(theme: theme, self: this),
                  _ => stepSyncStrategy(theme: theme, self: this),
                },
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.destructive,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildNavButtons(theme),
          ],
        ),
      ),
    );
  }

  /// 步骤指示器。
  Widget _buildStepIndicator(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_stepLabels.length, (i) {
            final isActive = i == _step;
            final isDone = i < _step;
            return Expanded(
              child: Row(
                children: [
                  _buildStepDot(theme, i, isActive, isDone),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _stepLabels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isActive || isDone ? FontWeight.w700 : FontWeight.normal,
                        color: isActive
                            ? theme.colorScheme.primary
                            : isDone
                                ? theme.colorScheme.foreground
                                : theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                  if (i < _stepLabels.length - 1) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: isDone
                            ? theme.colorScheme.primary
                            : theme.colorScheme.border,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _stepLabels.length,
            minHeight: 3,
            backgroundColor: theme.colorScheme.border,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDot(ShadThemeData theme, int index, bool isActive, bool isDone) {
    final color = isActive || isDone
        ? theme.colorScheme.primary
        : theme.colorScheme.border;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? color : null,
        border: Border.all(color: color, width: 1.5),
      ),
      child: isDone
          ? Icon(LucideIcons.check, size: 12, color: theme.colorScheme.background)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
            ),
    );
  }

  /// 底部导航。
  Widget _buildNavButtons(ShadThemeData theme) {
    final isLast = _step == 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step > 0) ...[
          ShadButton.outline(
            onPressed: _back,
            child: const Row(
              children: [
                Icon(LucideIcons.chevronLeft, size: 16),
                SizedBox(width: 2),
                Text('上一步'),
              ],
            ),
          ),
          const SizedBox(width: 10),
        ],
        ShadButton(
          onPressed: _saving ? null : _next,
          child: _saving
              ? const Text('保存中...')
              : Row(
                  children: [
                    Text(isLast ? '保存' : '下一步'),
                    if (!isLast) ...[
                      const SizedBox(width: 4),
                      const Icon(LucideIcons.chevronRight, size: 16),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
