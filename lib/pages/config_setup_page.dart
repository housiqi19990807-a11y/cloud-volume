// First-launch setup page writes the S3-compatible configuration file.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:macos_ui/macos_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_shell.dart';

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
  late final TextEditingController _bucketController;
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _prefixController;

  late bool _usePathStyle;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final config = widget.initialState.config;
    _endpointController = TextEditingController(text: config.endpoint);
    _regionController = TextEditingController(text: config.region);
    _bucketController = TextEditingController(text: config.bucket);
    _accessKeyController = TextEditingController(text: config.accessKeyId);
    _secretKeyController = TextEditingController(text: config.secretAccessKey);
    _prefixController = TextEditingController(text: config.rootPrefix);
    _usePathStyle = config.usePathStyle;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _regionController.dispose();
    _bucketController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = RemoteStorageConfig(
      endpoint: _endpointController.text,
      region: _regionController.text,
      bucket: _bucketController.text,
      accessKeyId: _accessKeyController.text,
      secretAccessKey: _secretKeyController.text,
      rootPrefix: _prefixController.text,
      usePathStyle: _usePathStyle,
    );

    if (!config.isConfigured) {
      setState(() {
        _errorText = '请至少填写 endpoint、bucket、access key ID 和 secret access key。';
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
    return AppWindowFrame(
      title: '初始化远程存储',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 4,
                  child: _SetupIntroCard(
                    configPath: widget.initialState.configPath,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: _buildFormCard(context)),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SetupIntroCard(configPath: widget.initialState.configPath),
              const SizedBox(height: 20),
              _buildFormCard(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final typography = MacosTheme.of(context).typography;
    final theme = MacosTheme.of(context);

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('初始化远程存储', style: typography.title1),
          const SizedBox(height: 10),
          Text(
            '填入兼容 S3 的对象存储连接信息。保存后会直接写入本地配置文件，并切换到已连接状态。',
            style: typography.body.copyWith(
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 24),
          _LabeledField(
            label: 'Endpoint',
            child: MacosTextField(
              controller: _endpointController,
              placeholder: 'https://s3.example.com',
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Bucket',
            child: MacosTextField(
              controller: _bucketController,
              placeholder: 'media-assets',
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Region',
            child: MacosTextField(
              controller: _regionController,
              placeholder: 'auto / us-east-1',
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Access Key ID',
            child: MacosTextField(
              controller: _accessKeyController,
              placeholder: 'AKIA...',
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Secret Access Key',
            child: MacosTextField(
              controller: _secretKeyController,
              placeholder: 'secret',
              obscureText: true,
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Root Prefix',
            child: MacosTextField(
              controller: _prefixController,
              placeholder: 'library/music',
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.canvasColor.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: <Widget>[
                MacosSwitch(
                  value: _usePathStyle,
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() {
                            _usePathStyle = value;
                          });
                        },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Use path-style access', style: typography.headline),
                      const SizedBox(height: 4),
                      Text(
                        '适合大多数 S3 兼容存储和本地对象存储网关。',
                        style: typography.subheadline.copyWith(
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_errorText != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: typography.body.copyWith(
                color: MacosColors.systemRedColor,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              PushButton(
                controlSize: ControlSize.large,
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? '保存中...' : '保存并继续'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupIntroCard extends StatelessWidget {
  const _SetupIntroCard({required this.configPath});

  final String configPath;

  @override
  Widget build(BuildContext context) {
    final typography = MacosTheme.of(context).typography;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const MacosIcon(
                CupertinoIcons.cloud_fill,
                size: 20,
                color: Color(0xFF226B74),
              ),
              const SizedBox(width: 10),
              Text('首次使用', style: typography.title2),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '把对象存储连接信息整理到一个稳定的本地入口，然后再接浏览、上传、同步等后续功能。',
            style: typography.largeTitle.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 22),
          Text('当前配置文件位置', style: typography.headline),
          const SizedBox(height: 8),
          SelectableText(
            configPath,
            style: typography.body.copyWith(color: CupertinoColors.label),
          ),
          const SizedBox(height: 22),
          Text(
            '建议先确认 endpoint、bucket 和鉴权信息可用；region 与 root prefix 可以后续再调整。',
            style: typography.body.copyWith(
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typography = MacosTheme.of(context).typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: typography.headline),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
