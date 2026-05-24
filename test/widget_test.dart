// Smoke test: verify the app boots and shows the Chinese bootstrap UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';

void main() {
  testWidgets('App shows Chinese setup page when config is missing', (
    tester,
  ) async {
    // Provide in-memory prefs so ThemeInitializer can resolve.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );

    // Allow ThemeInitializer + FutureBuilder to resolve.
    await tester.pumpAndSettle();

    expect(find.text('初始化配置'), findsOneWidget);
    expect(find.text('配置 S3 兼容存储的连接信息。'), findsOneWidget);
  });

  testWidgets('App shows Chinese home page when config exists', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: true)),
    );

    await tester.pumpAndSettle();

    expect(find.text('远程存储已连接'), findsOneWidget);
  });
}

/// A minimal fake API that does not need the Go bridge.
class _FakeApi implements RemoteStorageGateway {
  _FakeApi({required this.configured});

  final bool configured;

  @override
  Future<BootstrapState> loadBootstrapState() async {
    return BootstrapState(
      configPath: '/tmp/.remote-storage/config.toml',
      configured: configured,
      config: configured
          ? const RemoteStorageConfig(
              endpoint: 'https://s3.example.com',
              region: 'us-east-1',
              bucket: 'test-bucket',
              accessKeyId: 'AKIA_TEST',
              secretAccessKey: 'secret_test',
              rootPrefix: '',
              usePathStyle: true,
            )
          : RemoteStorageConfig.empty(),
    );
  }

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    return BootstrapState(
      configPath: '/tmp/.remote-storage/config.toml',
      configured: true,
      config: config,
    );
  }
}
