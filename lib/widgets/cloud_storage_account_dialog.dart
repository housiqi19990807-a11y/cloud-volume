// 新增/编辑账号弹窗：两步式引导（选择接入协议 → 配置连接信息）。
// 子窗口模式（asDialog: false）返回裸内容并用 MeasureSize 按内容自适应窗口尺寸；
// 默认应用内 ShadDialog；Debug 子窗口用 asDialog:false。编辑模式不走向导。
// 字段构建与协议选择卡片在 part 文件 cloud_storage_account_dialog_steps.dart 中。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/cloud_storage_account_draft.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/utils/account_config_builder.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/account_proxy_section.dart';
import 'package:remote_storage/widgets/baidu_pan_auth_section.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/widgets/measure_size.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    this.creatorWindowId,
    this.creatorFrameLeft,
    this.creatorFrameTop,
    this.creatorFrameWidth,
    this.creatorFrameHeight,
  });

  final Future<bool> Function(RemoteStorageConfig config) onSave;
  final Future<String> Function() onStartBaiduPanAuthorization;
  final Future<RemoteStorageConfig> Function(String displayName, String code)
  onAuthorizeBaiduPan;
  final RemoteStorageConfig? initialConfig;
  final bool editing;

  /// true = 应用内拟态框（默认）；false = Debug 子窗口裸内容。
  final bool asDialog;

  /// 子窗口模式保存成功后回调（关闭窗口）。
  final VoidCallback? onSaved;

  /// 子窗口模式取消时回调。
  final VoidCallback? onCancel;

  /// Parent frame for re-centering after content-fit resize (sub-window only).
  final String? creatorWindowId;
  final double? creatorFrameLeft;
  final double? creatorFrameTop;
  final double? creatorFrameWidth;
  final double? creatorFrameHeight;

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

  // -- Sub-window content-fit -------------------------------------------------

  /// Content width for the sub-window form body (shell adds horizontal padding).
  /// Wide enough for two-column connection fields without feeling sparse.
  static const double _contentWidth = 680;

  Size? _latestContentSize;
  int _fitGeneration = 0;
  bool _fitInFlight = false;

  void _onContentSize(Size contentSize) {
    if (widget.asDialog) return;
    if (contentSize.width <= 0 || contentSize.height <= 0) return;
    _latestContentSize = contentSize;
    _fitGeneration++;
    _drainContentFit();
  }

  Future<void> _drainContentFit() async {
    if (_fitInFlight || widget.asDialog) return;
    _fitInFlight = true;
    try {
      while (mounted && !widget.asDialog) {
        final gen = _fitGeneration;
        final size = _latestContentSize;
        if (size == null) break;
        try {
          await fitModalSubWindowToContentSize(
            size,
            creatorWindowId: widget.creatorWindowId,
            creatorFrameLeft: widget.creatorFrameLeft,
            creatorFrameTop: widget.creatorFrameTop,
            creatorFrameWidth: widget.creatorFrameWidth,
            creatorFrameHeight: widget.creatorFrameHeight,
          );
        } catch (_) {}
        if (gen == _fitGeneration) break;
      }
    } finally {
      _fitInFlight = false;
    }
  }

  Widget _wrapMeasured(Widget child) {
    if (widget.asDialog) return child;
    // Measure unconstrained content height at fixed form width; shell padding
    // and title bar are added inside fitModalSubWindowToContentSize.
    return MeasureSize(
      onChange: _onContentSize,
      contentWidth: _contentWidth,
      child: child,
    );
  }

  // -- Step navigation --------------------------------------------------------

  void _next() {
    if (_step < 1) {
      setState(() {
        _errorText = null;
        _step++;
      });
      return;
    }
    _submit();
  }

  void _back() {
    if (_step <= 0) return;
    setState(() {
      _errorText = null;
      _step--;
    });
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // Editing: single-screen form, no wizard chrome.
    if (widget.editing) {
      final content = _buildEditContent(theme);
      if (!widget.asDialog) return _wrapMeasured(content);
      return ShadDialog(
        title: const Text('编辑账号'),
        description: const Text(
          '修改账号连接信息；密钥、密码或 OAuth 授权会按你当前选择保留或更新。',
        ),
        constraints: const BoxConstraints(maxWidth: 680),
        scrollable: true,
        child: content,
      );
    }
    // New account: 2-step wizard. Sub-window measures shrink-wrapped content
    // and resizes the OS window to fit (no empty bottom / no inner scroll).
    if (!widget.asDialog) {
      return _wrapMeasured(_buildWizardContent(theme));
    }
    return ShadDialog(
      title: const Text('新增账号'),
      description: const Text('先选择存储类型，再填写对应的连接信息。'),
      constraints: const BoxConstraints(maxWidth: 680),
      scrollable: true,
      child: _buildWizardContent(theme),
    );
  }

  /// Shared wizard layout for both sub-window and dialog mode.
  Widget _buildWizardContent(ShadThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: 24),
        _buildNavButtons(theme),
      ],
    );
  }

  /// Editing mode: just the connection fields + nav buttons.
  Widget _buildEditContent(ShadThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stepConnectionFields(theme: theme, self: this),
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
        const SizedBox(height: 24),
        _buildEditNavButtons(theme),
      ],
    );
  }

  Widget _buildStepBody(ShadThemeData theme) {
    return switch (_step) {
      0 => stepProtocolPicker(theme: theme, self: this),
      _ => stepConnectionFields(theme: theme, self: this),
    };
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
                    Text(isLast ? '保存账号' : '下一步'),
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

  /// Editing mode nav buttons: just Cancel + Save.
  Widget _buildEditNavButtons(ShadThemeData theme) {
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
        ShadButton(
          onPressed: _saving ? null : _submit,
          child: _saving ? const Text('保存中...') : const Text('保存修改'),
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
