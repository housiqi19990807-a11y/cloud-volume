// 首次启动配置页：左右分栏布局，内容延伸至标题栏下方。
// 左侧：品牌面板。右侧：表单。组件拆分至 widgets/ 目录。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:remote_storage/widgets/config_right_form.dart';

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

  late bool _usePathStyle;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final config = widget.initialState.config;
    _endpointController = TextEditingController(text: config.endpoint);
    _regionController = TextEditingController(text: config.region);
    _accessKeyController = TextEditingController(text: config.accessKeyId);
    _secretKeyController = TextEditingController(text: config.secretAccessKey);
    _usePathStyle = config.usePathStyle;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = RemoteStorageConfig(
      endpoint: _endpointController.text,
      region: _regionController.text,
      bucket: widget.initialState.config.bucket,
      accessKeyId: _accessKeyController.text,
      secretAccessKey: _secretKeyController.text,
      rootPrefix: widget.initialState.config.rootPrefix,
      usePathStyle: _usePathStyle,
    );

    if (!config.isConfigured) {
      setState(() {
        _errorText = '端点地址、访问密钥 ID 和访问密钥为必填项。';
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
        _errorText = error.toString();
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
          Expanded(
            flex: 5,
            child: ConfigLeftPanel(configPath: widget.initialState.configPath),
          ),
          Expanded(
            flex: 7,
            child: ConfigRightFormPanel(
              endpointController: _endpointController,
              regionController: _regionController,
              accessKeyController: _accessKeyController,
              secretKeyController: _secretKeyController,
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
