// Bootstrap page decides whether the app should open setup flow or the ready state.

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/pages/config_setup_page.dart';
import 'package:remote_storage/pages/home_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_shell.dart';

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
            title: '检查配置中',
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

        return HomePage(
          state: session.state,
          onRefresh: _reload,
          onEditConfig: () {
            setState(() {
              _showSetupAnyway = true;
            });
          },
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
    final typography = MacosTheme.of(context).typography;
    return AppWindowFrame(
      title: 'Remote Storage',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: PanelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (loading) ...<Widget>[
                  const ProgressCircle(),
                  const SizedBox(height: 18),
                ],
                Text(title, style: typography.title1),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: typography.body.copyWith(
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PushButton(
                      controlSize: ControlSize.large,
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
