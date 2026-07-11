// 新增/编辑账号弹窗：两步式引导（选择接入协议 → 配置连接信息）。
// 子窗口模式（asDialog: false）返回裸内容；Web 回退仍用 ShadDialog。
// 编辑模式跳过步骤 1，直接进入连接信息。
// 字段构建与协议选择卡片在 part 文件 cloud_storage_account_dialog_steps.dart 中。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/cloud_storage_account_draft.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/utils/account_config_builder.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/account_proxy_section.dart';
import 'package:remote_storage/widgets/baidu_pan_auth_section.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

export 'package:remote_storage/models/cloud_storage_account_draft.dart';

part 'cloud_storage_account_dialog_steps.dart';

/// 账号管理页使用的新增/编辑账号对话框。
///
/// 保存时返回 [RemoteStorageConfig] 给调用方，由调用方决定 profileName 并保存。
class CloudStorageAccountDialog extends StatefulWidget {
  const CloudStorageAccountDialog({
    super.key,
    required this.onSave,
    required this.onStartBaiduPanAuthorization,
    required this.onAuthorizeBaiduPan,
    this.initialConfig,
    this.editing = false,
    this.asDialog = true,
    this.onSaved,
    this.onCancel,
  });

  final Future<bool> Function(RemoteStorageConfig config) onSave;
  final Future<String> Function() onStartBaiduPanAuthorization;
  final Future<RemoteStorageConfig> Function(String displayName, String code)
  onAuthorizeBaiduPan;
  final RemoteStorageConfig? initialConfig;
  final bool editing;

  /// true = ShadDialog 拟态框模式（Web 端），false = 裸内容（子窗口）。
  final bool asDialog;

  /// 子窗口模式保存成功后回调（关闭窗口）。
  final VoidCallback? onSaved;

  /// 子窗口模式取消时回调。
  final VoidCallback? onCancel;

  @override
  State<CloudStorageAccountDialog> createState() =>
      _CloudStorageAccountDialogState();
}

class _CloudStorageAccountDialogState extends State<CloudStorageAccountDialog> {
  StorageType _storageType = StorageType.s3;
  final _nameController = TextEditingController();
  final _mappedBucketNameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _regionController = TextEditingController(text: 'auto');
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _webdavUsernameController = TextEditingController();
  final _webdavPasswordController = TextEditingController();
  final _baiduAuthCodeController = TextEditingController();
  final _proxyHostController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _proxyUsernameController = TextEditingController();
  final _proxyPasswordController = TextEditingController();
  RemoteStorageConfig? _authorizedBaiduConfig;
  String _proxyMode = kAccountProxyModeInherit;
  String _proxyType = 'http';
  String _baiduAuthUrl = '';
  String? _baiduAuthErrorText;
  bool _openingBaiduAuthPage = false;
  bool _authorizingBaidu = false;
  bool _mappedBucketNameEdited = false;
  bool _usePathStyle = true;

  // Wizard state — step 0 = protocol picker, step 1 = connection fields.
  int _step = 0;
  bool _saving = false;
  String? _errorText;
  static const _stepLabels = ['选择协议', '连接信息'];

  // Sub-window sizes per step; step 1 varies by protocol field count.
  static const _sizeStep0 = Size(520, 500);
  static const _sizeStep1S3 = Size(520, 640);
  static const _sizeStep1WebDAV = Size(520, 540);
  static const _sizeStep1Baidu = Size(520, 420);

  /// Exposed for part-file step functions to trigger rebuilds.
  void markDirty(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    if (config == null) return;
    _storageType = config.storageType;
    _nameController.text = config.displayName;
    _mappedBucketNameController.text = config.mappedBucketName;
    _endpointController.text = config.endpoint;
    _regionController.text = config.region.isEmpty ? 'auto' : config.region;
    _accessKeyController.text = config.accessKeyId;
    _webdavUsernameController.text = config.webdavUsername;
    _usePathStyle = config.usePathStyle;
    _proxyMode = config.proxyMode;
    _proxyType = config.proxyType;
    _proxyHostController.text = config.proxyHost;
    _proxyPortController.text = config.proxyPort;
    _proxyUsernameController.text = config.proxyUsername;
    _proxyPasswordController.text = config.proxyPassword;
    if (config.storageType == StorageType.baiduPan) {
      _authorizedBaiduConfig = config;
    }
    // Editing an existing account: skip protocol selection.
    if (widget.editing) _step = 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mappedBucketNameController.dispose();
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    _baiduAuthCodeController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    super.dispose();
  }

  // -- Step navigation --------------------------------------------------------

  void _next() {
    if (_step < 1) {
      setState(() {
        _errorText = null;
        _step++;
      });
      _applySubWindowStepSize();
      return;
    }
    _submit();
  }

  void _back() => _goToStep(_step - 1);

  void _goToStep(int index) {
    if (index < 0 || index >= _stepLabels.length || index == _step) return;
    setState(() {
      _errorText = null;
      _step = index;
    });
    _applySubWindowStepSize();
  }

  Size _sizeForStep(int step) {
    if (step == 0) return _sizeStep0;
    return switch (_storageType) {
      StorageType.webdav => _sizeStep1WebDAV,
      StorageType.baiduPan => _sizeStep1Baidu,
      _ => _sizeStep1S3,
    };
  }

  Future<void> _applySubWindowStepSize() async {
    if (widget.asDialog) return;
    try {
      await resizeKeepingWindowCenter(_sizeForStep(_step));
      await windowManager.focus();
    } catch (_) {}
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (!widget.asDialog) return _buildSubWindowLayout(theme);
    return ShadDialog(
      title: Text(widget.editing ? '编辑账号' : '新增账号'),
      description: Text(
        widget.editing
            ? '修改账号连接信息；密钥、密码或 OAuth 授权会按你当前选择保留或更新。'
            : '先选择存储类型，再填写对应的连接信息。',
      ),
      constraints: const BoxConstraints(maxWidth: 480),
      scrollable: true,
      child: _buildDialogContent(theme),
    );
  }

  Widget _buildSubWindowLayout(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(theme),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: _buildStepBody(theme),
            ),
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildNavButtons(theme),
      ],
    );
  }

  Widget _buildDialogContent(ShadThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(theme),
        const SizedBox(height: 20),
        _buildStepBody(theme),
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
    );
  }

  Widget _buildStepBody(ShadThemeData theme) {
    return switch (_step) {
      0 => stepProtocolPicker(theme: theme, self: this),
      _ => stepConnectionFields(theme: theme, self: this),
    };
  }

  Widget _buildStepIndicator(ShadThemeData theme) {
    return Row(
      children: List.generate(_stepLabels.length, (i) {
        final isActive = i == _step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: i < _stepLabels.length - 1 ? 8 : 0,
            ),
            child: _buildStepTab(theme, i, isActive),
          ),
        );
      }),
    );
  }

  Widget _buildStepTab(ShadThemeData theme, int index, bool isActive) {
    final borderColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.border.withValues(alpha: 0.7);
    final bg = isActive
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.secondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _goToStep(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _stepLabels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButtons(ShadThemeData theme) {
    final isLast = _step == 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ShadButton.outline(
          onPressed: widget.asDialog
              ? () => Navigator.of(context).pop()
              : widget.onCancel,
          child: const Text('取消'),
        ),
        const SizedBox(width: 10),
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
                    Text(isLast
                        ? (widget.editing ? '保存修改' : '保存账号')
                        : '下一步'),
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

  // -- Submit & helpers -------------------------------------------------------
  // Protocol-specific field builders (_s3Fields / _webdavFields / _baiduPanFields)
  // live in the part file cloud_storage_account_dialog_steps.dart.

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final config = buildAccountConfig(
      CloudStorageAccountDraft(
        storageType: _storageType,
        name: _nameController.text.trim(),
        mappedBucketName: _mappedBucketNameController.text.trim(),
        endpoint: _endpointController.text,
        region: _regionController.text,
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
        usePathStyle: _usePathStyle,
        webdavUsername: _webdavUsernameController.text,
        webdavPassword: _webdavPasswordController.text,
        proxyMode: _proxyMode,
        proxyType: _proxyType,
        proxyHost: _proxyHostController.text.trim(),
        proxyPort: _proxyPortController.text.trim(),
        proxyUsername: _proxyUsernameController.text.trim(),
        proxyPassword: _proxyPasswordController.text,
      ),
      existing: widget.initialConfig,
      authorizedBaiduConfig: _authorizedBaiduConfig,
    );
    final saved = await widget.onSave(config);
    if (!mounted) return;
    if (saved) {
      widget.onSaved?.call();
      if (widget.asDialog) Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _errorText = '保存失败，请检查配置';
      });
    }
  }

  void _syncMappedBucketName() {
    if (widget.editing || _mappedBucketNameEdited) return;
    _mappedBucketNameController.text = _nameController.text;
  }

  // -- Baidu OAuth helpers ----------------------------------------------------

  Future<void> _authorizeBaiduPan() async {
    final code = _baiduAuthCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _baiduAuthErrorText = '请先粘贴百度授权页显示的授权码。');
      return;
    }
    setState(() {
      _authorizingBaidu = true;
      _baiduAuthErrorText = null;
    });
    try {
      final config = await widget.onAuthorizeBaiduPan(
        _nameController.text.trim(),
        code,
      );
      if (!mounted) return;
      setState(() {
        _authorizedBaiduConfig = config;
        _baiduAuthCodeController.clear();
        _baiduAuthErrorText = null;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = config.displayName;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _baiduAuthErrorText = describeBridgeError(error));
    } finally {
      if (mounted) setState(() => _authorizingBaidu = false);
    }
  }

  Future<void> _startBaiduPanAuthorization() async {
    setState(() {
      _openingBaiduAuthPage = true;
      _baiduAuthErrorText = null;
    });
    try {
      final authUrl = await widget.onStartBaiduPanAuthorization();
      if (!mounted) return;
      setState(() => _baiduAuthUrl = authUrl);
    } catch (error) {
      if (!mounted) return;
      setState(() => _baiduAuthErrorText = describeBridgeError(error));
    } finally {
      if (mounted) setState(() => _openingBaiduAuthPage = false);
    }
  }
}
