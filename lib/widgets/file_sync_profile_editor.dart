// 文件同步配置编辑弹窗：新增或修改一条同步配置。
// 全部使用 shadcn_ui 控件，样式与账号编辑弹窗保持一致。
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileSyncProfileEditor extends StatefulWidget {
  const FileSyncProfileEditor({
    super.key,
    required this.profiles,
    required this.onSave,
    this.initial,
  });

  /// 已有账号 profile 列表，供选择关联账号。
  final List<ProfileInfo> profiles;
  final Future<bool> Function(SyncProfile profile) onSave;
  final SyncProfile? initial;

  @override
  State<FileSyncProfileEditor> createState() => _FileSyncProfileEditorState();
}

class _FileSyncProfileEditorState extends State<FileSyncProfileEditor> {
  final _nameController = TextEditingController();
  final _bucketController = TextEditingController();
  final _remotePrefixController = TextEditingController();
  final _localPathController = TextEditingController();
  final _excludeController = TextEditingController();

  String _accountProfile = '';
  SyncDirection _direction = SyncDirection.twoway;
  SyncConflictPolicy _conflictPolicy = SyncConflictPolicy.newest;
  int _intervalSeconds = 300;
  int _quietSeconds = 10;
  bool _enabled = true;
  bool _saving = false;
  String? _errorText;

  static const _intervalOptions = <int>[60, 120, 300, 600, 1800, 3600];
  static const _quietOptions = <int>[0, 5, 10, 30, 60, 120];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (widget.profiles.isNotEmpty) {
      _accountProfile = widget.profiles.first.name;
    }
    if (initial == null) {
      return;
    }
    _nameController.text = initial.name;
    _accountProfile = initial.accountProfile;
    _bucketController.text = initial.bucket;
    _remotePrefixController.text = initial.remotePrefix;
    _localPathController.text = initial.localPath;
    _direction = initial.direction;
    _conflictPolicy = initial.conflictPolicy;
    _intervalSeconds = initial.intervalSeconds;
    _quietSeconds = initial.quietSeconds;
    _excludeController.text = initial.excludePatterns.join('\n');
    _enabled = initial.enabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bucketController.dispose();
    _remotePrefixController.dispose();
    _localPathController.dispose();
    _excludeController.dispose();
    super.dispose();
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
    final name = _nameController.text.trim();
    final bucket = _bucketController.text.trim();
    final localPath = _localPathController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '请输入配置名称');
      return;
    }
    if (localPath.isEmpty) {
      setState(() => _errorText = '请选择本地目录');
      return;
    }
    if (bucket.isEmpty) {
      setState(() => _errorText = '请输入远端桶名');
      return;
    }
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
      accountProfile: _accountProfile,
      bucket: bucket,
      remotePrefix: _remotePrefixController.text.trim(),
      localPath: localPath,
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
    if (!mounted) {
      return;
    }
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
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(theme, '配置名称'),
              ShadInput(
                controller: _nameController,
                placeholder: const Text('例如：工作文档同步'),
              ),
              const SizedBox(height: 14),
              _label(theme, '关联账号'),
              _accountSelect(theme),
              const SizedBox(height: 14),
              _label(theme, '远端桶名'),
              ShadInput(
                controller: _bucketController,
                placeholder: const Text('例如：my-bucket'),
              ),
              const SizedBox(height: 14),
              _label(theme, '远端目录前缀（可留空）'),
              ShadInput(
                controller: _remotePrefixController,
                placeholder: const Text('例如：docs/work'),
              ),
              const SizedBox(height: 14),
              _label(theme, '本地目录'),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: _localPathController,
                      placeholder: const Text('点击右侧按钮选择目录'),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.secondary(
                    onPressed: _pickLocalDirectory,
                    child: const Text('选择'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _label(theme, '同步方向'),
              _directionSelect(theme),
              const SizedBox(height: 14),
              _label(theme, '冲突策略'),
              _conflictSelect(theme),
              const SizedBox(height: 14),
              _label(theme, '同步周期'),
              _intervalSelect(theme),
              const SizedBox(height: 14),
              _label(theme, '热数据静默时间（秒）'),
              _quietSelect(theme),
              const SizedBox(height: 6),
              Text(
                '文件写入后静默该秒数才纳入同步，避免正在编辑的文件频繁上传。',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 14),
              _label(theme, '排除规则（每行一条）'),
              ShadInput(
                controller: _excludeController,
                placeholder: const Text('.DS_Store\n*.tmp'),
                maxLines: 4,
              ),
              const SizedBox(height: 14),
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
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ],
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  ShadButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? '保存中...' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ShadThemeData theme, String text) {
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

  Widget _accountSelect(ShadThemeData theme) {
    if (widget.profiles.isEmpty) {
      return Text(
        '暂无已配置账号，请先在账号管理中添加。',
        style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
      );
    }
    return ShadSelect<String>(
      initialValue: _accountProfile,
      placeholder: const Text('选择账号'),
      selectedOptionBuilder: (context, value) => Text(value),
      options: widget.profiles
          .map((p) => ShadOption<String>(value: p.name, child: Text(p.name)))
          .toList(growable: false),
      onChanged: (v) {
        if (v != null) setState(() => _accountProfile = v);
      },
    );
  }

  Widget _directionSelect(ShadThemeData theme) {
    return ShadSelect<String>(
      initialValue: _direction.value,
      selectedOptionBuilder: (context, value) =>
          Text(SyncDirection.fromValue(value).label),
      options: SyncDirection.values
          .map((d) => ShadOption<String>(
                value: d.value,
                child: Text(d.label),
              ))
          .toList(growable: false),
      onChanged: (v) {
        if (v != null) setState(() => _direction = SyncDirection.fromValue(v));
      },
    );
  }

  Widget _conflictSelect(ShadThemeData theme) {
    return ShadSelect<String>(
      initialValue: _conflictPolicy.value,
      selectedOptionBuilder: (context, value) =>
          Text(SyncConflictPolicy.fromValue(value).label),
      options: SyncConflictPolicy.values
          .map((p) => ShadOption<String>(
                value: p.value,
                child: Text(p.label),
              ))
          .toList(growable: false),
      onChanged: (v) {
        if (v != null) {
          setState(() => _conflictPolicy = SyncConflictPolicy.fromValue(v));
        }
      },
    );
  }

  Widget _intervalSelect(ShadThemeData theme) {
    return ShadSelect<int>(
      initialValue: _intervalSeconds,
      selectedOptionBuilder: (context, value) => Text(_intervalLabel(value)),
      options: _intervalOptions
          .map((s) => ShadOption<int>(value: s, child: Text(_intervalLabel(s))))
          .toList(growable: false),
      onChanged: (v) {
        if (v != null) setState(() => _intervalSeconds = v);
      },
    );
  }

  Widget _quietSelect(ShadThemeData theme) {
    return ShadSelect<int>(
      initialValue: _quietSeconds,
      selectedOptionBuilder: (context, value) => Text(_quietLabel(value)),
      options: _quietOptions
          .map((s) => ShadOption<int>(value: s, child: Text(_quietLabel(s))))
          .toList(growable: false),
      onChanged: (v) {
        if (v != null) setState(() => _quietSeconds = v);
      },
    );
  }

  static String _intervalLabel(int seconds) {
    if (seconds >= 3600) {
      return '${seconds ~/ 3600} 小时';
    }
    if (seconds >= 60) {
      return '${seconds ~/ 60} 分钟';
    }
    return '$seconds 秒';
  }

  static String _quietLabel(int seconds) {
    if (seconds == 0) return '0 秒（实时）';
    if (seconds >= 60) return '${seconds ~/ 60} 分钟';
    return '$seconds 秒';
  }
}
