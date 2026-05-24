// Smoke test: verify the app boots and shows the Chinese bootstrap UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/pages/file_manager_page.dart';

void main() {
  testWidgets('App shows setup page when config is missing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录远程存储'), findsOneWidget);
  });

  testWidgets('App shows main layout when config exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FileManagerPage), findsOneWidget);
  });
}

/// Minimal fake API that does not need the Go bridge.
class _FakeApi implements RemoteStorageGateway {
  _FakeApi({required this.configured});
  final bool configured;

  @override
  Future<BootstrapState> loadBootstrapState() async => BootstrapState(
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

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async =>
      BootstrapState(
        configPath: '/tmp/.remote-storage/config.toml',
        configured: true,
        config: config,
      );

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async => [];

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async => [];

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
  ) async {}

  @override
  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
  ) async {}

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async =>
      RemoteStorageConfig.empty();

  @override
  Future<List<ProfileInfo>> listProfiles() async => [];
}
