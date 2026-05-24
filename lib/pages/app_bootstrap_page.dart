// 启动引导页：判断是否已有配置，决定跳转配置页还是主界面。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/pages/config_setup_page.dart';
import 'package:remote_storage/pages/main_layout_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key, required this.apiFactory});

  final RemoteStorageApiFactory apiFactory;

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  late Future<_BootstrapSession> _sessionFuture;
  bool _showSetupAnyway = false;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _loadSession();
  }

  Future<_BootstrapSession> _loadSession() async {
    final api = await widget.apiFactory();
    final state = await api.loadBootstrapState();
    return _BootstrapSession(api: api, state: state);
  }

  void _reload() {
    setState(() {
      _showSetupAnyway = false;
      _sessionFuture = _loadSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapMessageView(
            title: '正在检查配置',
            description: '正在读取 ~/.remote-storage/config.toml 并准备远程存储环境。',
            loading: true,
          );
        }

        if (snapshot.hasError) {
          return _BootstrapMessageView(
            title: '启动失败',
            description: snapshot.error.toString(),
            actionLabel: '重试',
            onAction: _reload,
          );
        }

        final session = snapshot.data!;
        final shouldShowSetup = _showSetupAnyway || !session.state.configured;
        if (shouldShowSetup) {
          return ConfigSetupPage(
            api: session.api,
            initialState: session.state,
            onSaved: _reload,
          );
        }

        return MainLayoutPage(
          state: session.state,
          api: session.api,
          onEditConfig: () => setState(() => _showSetupAnyway = true),
          onRefresh: _reload,
        );
      },
    );
  }
}

class _BootstrapSession {
  const _BootstrapSession({required this.api, required this.state});

  final RemoteStorageGateway api;
  final BootstrapState state;
}

class _BootstrapMessageView extends StatelessWidget {
  const _BootstrapMessageView({
    required this.title,
    required this.description,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: ShadCard(
            width: 480,
            padding: const EdgeInsets.all(32),
            title: Text(title),
            description: Text(
              description,
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            child: Column(
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: CircularProgressIndicator(),
                  ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
