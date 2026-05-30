// 首次启动配置页：左右等分布局，内容延伸至标题栏下方。
// 左侧：品牌面板。右侧：表单。组件拆分至 widgets/ 目录。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:remote_storage/widgets/config_right_form.dart';

// 首次运行预设默认值。
const _kDefaultEndpoint = 'https://fgws3-ocloud.ihep.ac.cn';
const _kDefaultRegion = 'auto';

class ConfigSetupPage extends StatefulWidget {
  const ConfigSetupPage({
    super.key,
    required this.api,
    required this.initialState,
    required this.onSaved,
  });

  final RemoteStorageGateway api;
  final BootstrapState initialState;
  final VoidCallback onSaved;

  @override
  State<ConfigSetupPage> createState() => _ConfigSetupPageState();
}

class _ConfigSetupPageState extends State<ConfigSetupPage> {
  late final TextEditingController _endpointController;
  late final TextEditingController _regionController;
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _webdavUsernameController;
  late final TextEditingController _webdavPasswordController;

  late bool _usePathStyle;
  bool _isSaving = false;
  String? _errorText;

  bool get _requiresWebdavSetup => widget.api.capabilities.supportsSessionLogin;

  @override
  void initState() {
    super.initState();
    final config = widget.initialState.config;
    // 首次运行时使用默认值。
    _endpointController = TextEditingController(
      text: config.endpoint.trim().isNotEmpty
          ? config.endpoint
          : _kDefaultEndpoint,
    );
    _regionController = TextEditingController(
      text: config.region.trim().isNotEmpty ? config.region : _kDefaultRegion,
    );
    _accessKeyController = TextEditingController(text: config.accessKeyId);
    _secretKeyController = TextEditingController();
    _webdavUsernameController = TextEditingController(text: config.webdavUsername);
    _webdavPasswordController = TextEditingController();
    _usePathStyle = config.usePathStyle;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = RemoteStorageConfig(
      endpoint: _endpointController.text,
      region: _regionController.text,
      bucket: widget.initialState.config.bucket,
      accessKeyId: _accessKeyController.text,
      secretAccessKey: _secretKeyController.text,
      hasSecretAccessKey: widget.initialState.config.hasSecretAccessKey,
      webdavUsername: _webdavUsernameController.text,
      webdavPassword: _webdavPasswordController.text,
      hasWebdavPassword: widget.initialState.config.hasWebdavPassword,
      rootPrefix: widget.initialState.config.rootPrefix,
      defaultDownloadDirectory:
          widget.initialState.config.defaultDownloadDirectory,
      hideDotFiles: widget.initialState.config.hideDotFiles,
      // 文件浏览固定为单击打开，配置阶段不再暴露这个开关。
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: widget.initialState.config.trashDirectoryName,
      trashRetentionDays: widget.initialState.config.trashRetentionDays,
      usePathStyle: _usePathStyle,
      windowsMountMode: widget.initialState.config.windowsMountMode,
      windowsThisPcEntryEnabled:
          widget.initialState.config.windowsThisPcEntryEnabled,
      windowsWritebackConcurrency:
          widget.initialState.config.windowsWritebackConcurrency,
    );

    if (!config.isConfigured) {
      setState(() {
        _errorText = '访问密钥 ID 和访问密钥为必填项。';
      });
      return;
    }
    if (_requiresWebdavSetup && !config.hasWebDavCredentials) {
      setState(() {
        _errorText = 'Web 端首次初始化还需要配置 WebDAV 账号和密码。';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await widget.api.saveConfig(config);
      if (!mounted) return;
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 左右等分，视觉更平衡。
          Expanded(
            child: ConfigLeftPanel(configPath: widget.initialState.configPath),
          ),
          Expanded(
            child: ConfigRightFormPanel(
              endpointController: _endpointController,
              regionController: _regionController,
              accessKeyController: _accessKeyController,
              secretKeyController: _secretKeyController,
              hasStoredSecretKey: widget.initialState.config.hasSecretAccessKey,
              showWebDavFields: _requiresWebdavSetup,
              webdavUsernameController: _webdavUsernameController,
              webdavPasswordController: _webdavPasswordController,
              hasStoredWebdavPassword:
                  widget.initialState.config.hasWebdavPassword,
              usePathStyle: _usePathStyle,
              onPathStyleChanged: (v) => setState(() => _usePathStyle = v),
              isSaving: _isSaving,
              errorText: _errorText,
              onSave: _save,
            ),
          ),
        ],
      ),
    );
  }
}
