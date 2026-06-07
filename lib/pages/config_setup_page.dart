// 首次启动配置页：左右等分布局，内容延伸至标题栏下方。
// 左侧：品牌面板。右侧：表单。组件拆分至 widgets/ 目录。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:remote_storage/widgets/config_right_form.dart';
import 'package:remote_storage/widgets/config_storage_type_step.dart';

// 首次运行预设默认值。
const _kDefaultEndpoint = 'https://fgws3-ocloud.ihep.ac.cn';
const _kDefaultRegion = 'auto';

enum _SetupStep { chooseType, accountForm }

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
  late final TextEditingController _mappedBucketNameController;
  late final TextEditingController _regionController;
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _webdavUsernameController;
  late final TextEditingController _webdavPasswordController;

  _SetupStep _step = _SetupStep.chooseType;
  late StorageType _storageType;
  late bool _usePathStyle;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final config = widget.initialState.config;
    _storageType = config.storageType;
    // 首次运行时使用默认值。
    _mappedBucketNameController = TextEditingController(
      text: config.mappedBucketName.trim().isNotEmpty
          ? config.mappedBucketName
          : config.storageType == StorageType.webdav
          ? 'WebDAV'
          : 'S3',
    );
    _endpointController = TextEditingController(
      text: config.endpoint.trim().isNotEmpty
          ? config.endpoint
          : config.storageType == StorageType.s3
          ? _kDefaultEndpoint
          : '',
    );
    _regionController = TextEditingController(
      text: config.region.trim().isNotEmpty ? config.region : _kDefaultRegion,
    );
    _accessKeyController = TextEditingController(text: config.accessKeyId);
    _secretKeyController = TextEditingController();
    _webdavUsernameController = TextEditingController(
      text: config.webdavUsername,
    );
    _webdavPasswordController = TextEditingController();
    _usePathStyle = config.usePathStyle;
  }

  @override
  void dispose() {
    _mappedBucketNameController.dispose();
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    super.dispose();
  }

  void _selectStorageType(StorageType type) {
    setState(() {
      _storageType = type;
      if (type == StorageType.s3 && _endpointController.text.trim().isEmpty) {
        _endpointController.text = _kDefaultEndpoint;
      }
      if (type == StorageType.webdav &&
          _endpointController.text.trim() == _kDefaultEndpoint) {
        _endpointController.clear();
      }
      final mappedName = _mappedBucketNameController.text.trim();
      if (mappedName.isEmpty || mappedName == 'S3' || mappedName == 'WebDAV') {
        _mappedBucketNameController.text = type == StorageType.webdav
            ? 'WebDAV'
            : 'S3';
      }
    });
  }

  Future<void> _save() async {
    final isWebDav = _storageType == StorageType.webdav;
    final config = RemoteStorageConfig(
      endpoint: _endpointController.text,
      storageType: _storageType,
      providerType: widget.initialState.config.providerType,
      displayName: widget.initialState.config.displayName,
      mappedBucketName: _mappedBucketNameController.text.trim().isNotEmpty
          ? _mappedBucketNameController.text
          : widget.initialState.config.displayName,
      region: _regionController.text,
      bucket: widget.initialState.config.bucket,
      accessKeyId: isWebDav ? '' : _accessKeyController.text,
      secretAccessKey: isWebDav ? '' : _secretKeyController.text,
      hasSecretAccessKey:
          !isWebDav && widget.initialState.config.hasSecretAccessKey,
      webdavUsername: isWebDav
          ? _webdavUsernameController.text
          : _accessKeyController.text,
      webdavPassword: isWebDav
          ? _webdavPasswordController.text
          : _secretKeyController.text,
      hasWebdavPassword:
          isWebDav && widget.initialState.config.hasWebdavPassword,
      rootPrefix: widget.initialState.config.rootPrefix,
      defaultDownloadDirectory:
          widget.initialState.config.defaultDownloadDirectory,
      cacheDirectory: widget.initialState.config.cacheDirectory,
      resolvedCacheDirectory: widget.initialState.config.resolvedCacheDirectory,
      hideDotFiles: widget.initialState.config.hideDotFiles,
      // 文件浏览固定为单击打开，配置阶段不再暴露这个开关。
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: widget.initialState.config.trashDirectoryName,
      trashRetentionDays: widget.initialState.config.trashRetentionDays,
      bucketSettings: widget.initialState.config.bucketSettings,
      writebackQuietSeconds: widget.initialState.config.writebackQuietSeconds,
      usePathStyle: _usePathStyle,
      windowsMountMode: widget.initialState.config.windowsMountMode,
      windowsThisPcEntryEnabled:
          widget.initialState.config.windowsThisPcEntryEnabled,
      windowsWritebackConcurrency:
          widget.initialState.config.windowsWritebackConcurrency,
    );

    if (!config.isConfigured) {
      setState(() {
        _errorText = isWebDav
            ? '请填写 WebDAV 地址、用户名和密码。'
            : '请填写 Endpoint、Access Key 和 Secret Key。';
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
            child: _step == _SetupStep.chooseType
                ? ConfigStorageTypeStep(
                    selectedType: _storageType,
                    onTypeChanged: _selectStorageType,
                    onNext: () => setState(() {
                      _errorText = null;
                      _step = _SetupStep.accountForm;
                    }),
                  )
                : ConfigRightFormPanel(
                    storageType: _storageType,
                    mappedBucketNameController: _mappedBucketNameController,
                    endpointController: _endpointController,
                    regionController: _regionController,
                    accessKeyController: _accessKeyController,
                    secretKeyController: _secretKeyController,
                    hasStoredSecretKey:
                        widget.initialState.config.hasSecretAccessKey,
                    webdavUsernameController: _webdavUsernameController,
                    webdavPasswordController: _webdavPasswordController,
                    hasStoredWebdavPassword:
                        widget.initialState.config.hasWebdavPassword,
                    usePathStyle: _usePathStyle,
                    onPathStyleChanged: (v) =>
                        setState(() => _usePathStyle = v),
                    isSaving: _isSaving,
                    errorText: _errorText,
                    onSave: _save,
                    onBack: () => setState(() {
                      _errorText = null;
                      _step = _SetupStep.chooseType;
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}
