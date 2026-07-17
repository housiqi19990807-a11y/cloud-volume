// Mount settings dialog separates access mode from platform-specific presentation.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/mount_engine_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum _MountPresentation { driveLetter, path }

Future<MountBucketOptions?> showMountBucketDialog(
  BuildContext context, {
  required String bucket,
  bool showWindowsMountMode = false,
  List<String> availableDriveLetters = const <String>[],
  WindowsMountEngine? currentEngine,
  bool winFspAvailable = false,
}) {
  return showAppModal<MountBucketOptions?>(
    context: context,
    builder: (dialogContext) => _MountBucketDialog(
      bucket: bucket,
      showWindowsMountMode: showWindowsMountMode,
      availableDriveLetters: availableDriveLetters,
      currentEngine: currentEngine,
      winFspAvailable: winFspAvailable,
    ),
  );
}

class _MountBucketDialog extends StatefulWidget {
  const _MountBucketDialog({
    required this.bucket,
    required this.showWindowsMountMode,
    required this.availableDriveLetters,
    required this.currentEngine,
    required this.winFspAvailable,
  });

  final String bucket;
  final bool showWindowsMountMode;
  final List<String> availableDriveLetters;
  final WindowsMountEngine? currentEngine;
  final bool winFspAvailable;

  @override
  State<_MountBucketDialog> createState() => _MountBucketDialogState();
}

class _MountBucketDialogState extends State<_MountBucketDialog> {
  String _mountPath = '';
  bool _readOnly = false;
  late _MountPresentation _presentation;
  String? _driveLetter;
  WindowsMountEngine? _engine;

  @override
  void initState() {
    super.initState();
    final hasDrive = widget.availableDriveLetters.isNotEmpty;
    _presentation = widget.showWindowsMountMode && hasDrive
        ? _MountPresentation.driveLetter
        : _MountPresentation.path;
    _driveLetter = hasDrive ? widget.availableDriveLetters.first : null;
    // When WinFsp is not installed the picker hides it; fall back to Cloud
    // Files so the selected value always reflects something mountable.
    _engine = (widget.currentEngine == WindowsMountEngine.winFsp &&
            !widget.winFspAvailable)
        ? WindowsMountEngine.cloudFiles
        : widget.currentEngine;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final usesPath = _presentation == _MountPresentation.path;
    return ShadDialog(
      title: const Text('挂载存储桶'),
      description: Text('配置 ${widget.bucket} 的本地挂载。'),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadSwitch(
              value: _readOnly,
              onChanged: (value) => setState(() => _readOnly = value),
              label: Text(
                '只读挂载',
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              sublabel: const Text('关闭时允许在挂载目录中新增、修改和删除文件。'),
            ),
            if (widget.showWindowsMountMode && _engine != null) ...[
              const SizedBox(height: 18),
              MountEnginePicker(
                theme: theme,
                engine: _engine!,
                winFspAvailable: widget.winFspAvailable,
                onChanged: (value) => setState(() => _engine = value),
              ),
            ],
            if (widget.showWindowsMountMode) ...[
              const SizedBox(height: 18),
              _FieldLabel(text: '挂载模式', theme: theme),
              const SizedBox(height: 8),
              ShadSelect<_MountPresentation>(
                key: ValueKey<_MountPresentation>(_presentation),
                minWidth: 440,
                initialValue: _presentation,
                selectedOptionBuilder: (context, value) =>
                    Text(_presentationLabel(value)),
                options: [
                  if (widget.availableDriveLetters.isNotEmpty)
                    const ShadOption<_MountPresentation>(
                      value: _MountPresentation.driveLetter,
                      child: Text('分配盘符'),
                    ),
                  const ShadOption<_MountPresentation>(
                    value: _MountPresentation.path,
                    child: Text('路径挂载'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _presentation = value);
                },
              ),
              if (widget.availableDriveLetters.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '当前没有可分配的盘符，请使用路径挂载。',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ],
            if (widget.showWindowsMountMode && !usesPath) ...[
              const SizedBox(height: 16),
              _FieldLabel(text: '盘符', theme: theme),
              const SizedBox(height: 8),
              ShadSelect<String>(
                key: ValueKey<String?>(_driveLetter),
                minWidth: 440,
                initialValue: _driveLetter,
                ensureSelectedVisible: false,
                selectedOptionBuilder: (context, value) => Text(value),
                options: widget.availableDriveLetters
                    .map(
                      (letter) => ShadOption<String>(
                        value: letter,
                        child: Text(letter),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) =>
                    setState(() => _driveLetter = value),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 15,
                    color: theme.colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '映射盘符只是将本地同步目录映射到盘符入口，不代表云存储的真实容量。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (!widget.showWindowsMountMode || usesPath) ...[
              const SizedBox(height: 16),
              _PathPicker(
                theme: theme,
                mountPath: _mountPath,
                onPick: _pickDirectory,
                onReset: _mountPath.isEmpty
                    ? null
                    : () => setState(() => _mountPath = ''),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                ShadButton(
                  onPressed: _canSubmit
                      ? () => Navigator.of(context).pop(
                          MountBucketOptions(
                            mountPath: usesPath ? _mountPath : '',
                            readOnly: _readOnly,
                            driveLetter: usesPath ? '' : _driveLetter ?? '',
                            windowsMountEngine:
                                widget.showWindowsMountMode ? _engine : null,
                          ),
                        )
                      : null,
                  child: const Text('开始挂载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit =>
      _presentation == _MountPresentation.path || _driveLetter != null;

  Future<void> _pickDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择挂载路径',
      initialDirectory: _mountPath.trim().isEmpty ? null : _mountPath.trim(),
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _mountPath = path.trim());
  }
}

class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.theme,
    required this.mountPath,
    required this.onPick,
    required this.onReset,
  });

  final ShadThemeData theme;
  final String mountPath;
  final VoidCallback onPick;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final hasCustomPath = mountPath.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: '挂载路径', theme: theme),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            hasCustomPath ? mountPath : '使用系统默认挂载路径',
            style: TextStyle(
              fontSize: 12,
              color: hasCustomPath
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ShadButton.outline(onPressed: onPick, child: const Text('选择路径')),
            const SizedBox(width: 10),
            ShadButton.outline(onPressed: onReset, child: const Text('使用默认')),
          ],
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, required this.theme});

  final String text;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.foreground,
      ),
    );
  }
}

String _presentationLabel(_MountPresentation value) {
  return switch (value) {
    _MountPresentation.driveLetter => '分配盘符',
    _MountPresentation.path => '路径挂载',
  };
}

