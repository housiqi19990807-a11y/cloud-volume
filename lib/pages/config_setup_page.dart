// 首次启动配置页：居中的圆角登录壳，左侧品牌面板，右侧表单。
// 组件拆分至 widgets/ 目录，便于单独调整布局与滚动行为。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:remote_storage/widgets/config_right_form.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

  late bool _usePathStyle;
  bool _isSaving = false;
  String? _errorText;

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
      defaultDownloadDirectory:
          widget.initialState.config.defaultDownloadDirectory,
      hideDotFiles: widget.initialState.config.hideDotFiles,
      // 文件浏览固定为单击打开，配置阶段不再暴露这个开关。
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: widget.initialState.config.trashDirectoryName,
      trashRetentionDays: widget.initialState.config.trashRetentionDays,
      usePathStyle: _usePathStyle,
      windowsMountMode: widget.initialState.config.windowsMountMode,
    );

    if (!config.isConfigured) {
      setState(() {
        _errorText = '访问密钥 ID 和访问密钥为必填项。';
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
    final theme = ShadTheme.of(context);
    final pageBackground = Color.lerp(
      const Color(0xffeef2f8),
      theme.colorScheme.background,
      0.28,
    )!;

    return Scaffold(
      backgroundColor: pageBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final shellWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth - 40
              : 1240.0;
          final shellHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight - 40
              : 760.0;
          final shell = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: shellWidth.clamp(960.0, 1240.0).toDouble(),
              maxHeight: shellHeight.clamp(640.0, 820.0).toDouble(),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.background,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: theme.colorScheme.border.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Row(
                  children: [
                    // 左右等分，视觉更平衡。
                    Expanded(
                      child: ConfigLeftPanel(
                        configPath: widget.initialState.configPath,
                      ),
                    ),
                    Expanded(
                      child: ConfigRightFormPanel(
                        endpointController: _endpointController,
                        regionController: _regionController,
                        accessKeyController: _accessKeyController,
                        secretKeyController: _secretKeyController,
                        usePathStyle: _usePathStyle,
                        onPathStyleChanged: (v) =>
                            setState(() => _usePathStyle = v),
                        isSaving: _isSaving,
                        errorText: _errorText,
                        onSave: _save,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          return Center(
            child: Padding(padding: const EdgeInsets.all(20), child: shell),
          );
        },
      ),
    );
  }
}
