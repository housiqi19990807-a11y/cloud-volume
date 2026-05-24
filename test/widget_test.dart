import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';

// Widget tests verify first-launch routing without loading the real Go bridge.
void main() {
  testWidgets('shows setup page when config is missing', (
    WidgetTester tester,
  ) async {
    final gateway = _FakeGateway(
      const BootstrapState(
        configPath: '/Users/test/.remote-storage/config.toml',
        configured: false,
        config: RemoteStorageConfig(
          endpoint: '',
          region: '',
          bucket: '',
          accessKeyId: '',
          secretAccessKey: '',
          rootPrefix: '',
          usePathStyle: true,
        ),
      ),
    );

    await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => gateway));
    await tester.pumpAndSettle();

    expect(find.text('保存并继续'), findsOneWidget);
    expect(find.textContaining('.remote-storage/config.toml'), findsOneWidget);
  });

  testWidgets('shows ready page when config exists', (
    WidgetTester tester,
  ) async {
    final gateway = _FakeGateway(
      const BootstrapState(
        configPath: '/Users/test/.remote-storage/config.toml',
        configured: true,
        config: RemoteStorageConfig(
          endpoint: 'https://s3.example.com',
          region: 'auto',
          bucket: 'media',
          accessKeyId: 'key',
          secretAccessKey: 'secret',
          rootPrefix: 'library',
          usePathStyle: true,
        ),
      ),
    );

    await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => gateway));
    await tester.pumpAndSettle();

    expect(find.text('远程存储已连接'), findsOneWidget);
    expect(find.text('编辑配置'), findsOneWidget);
  });
}

class _FakeGateway implements RemoteStorageGateway {
  _FakeGateway(this._state);

  BootstrapState _state;

  @override
  Future<BootstrapState> loadBootstrapState() async => _state;

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    _state = BootstrapState(
      configPath: _state.configPath,
      configured: true,
      config: config,
    );
    return _state;
  }
}
