// File manager delete-state tests cover stale listings after successful deletes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(TransferQueue.instance.resetForTest);
  tearDown(TransferQueue.instance.resetForTest);

  testWidgets('successful directory delete ignores a stale refresh row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _StaleDeleteApi();
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: FileManagerPage(
            api: api,
            config: RemoteStorageConfig.empty(),
            profiles: const [],
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('bucket-a'));
    await tester.pumpAndSettle();

    var browser = tester.widget<FileManagerObjectBrowser>(
      find.byType(FileManagerObjectBrowser),
    );
    expect(browser.objects, contains(api.directory));

    browser.onObjectAction(api.directory, FileObjectAction.delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ShadButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    browser = tester.widget<FileManagerObjectBrowser>(
      find.byType(FileManagerObjectBrowser),
    );
    expect(browser.deletingKeys, contains(api.directory.key));

    api.completeDelete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    browser = tester.widget<FileManagerObjectBrowser>(
      find.byType(FileManagerObjectBrowser),
    );
    expect(api.forceRefreshCount, 1);
    expect(browser.objects, isEmpty);
    expect(browser.deletingKeys, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}

class _StaleDeleteApi implements RemoteStorageGateway {
  final Completer<void> _deleteCompleter = Completer<void>();
  final ObjectInfo directory = const ObjectInfo(
    key: 'data/',
    size: 0,
    isDir: true,
  );
  int forceRefreshCount = 0;

  @override
  RemoteStorageCapabilities get capabilities => const RemoteStorageCapabilities(
    supportsMounts: false,
    supportsNativeOpen: false,
    supportsDownloadDirectory: false,
    supportsSessionLogin: false,
    supportsWebDavAccess: false,
    supportsBrowserTransfers: false,
    supportsDesktopWindowControls: false,
    supportsCacheDirectoryOpen: false,
  );

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async =>
      const <BucketInfo>[BucketInfo(name: 'bucket-a')];

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String bucket,
  ) async => BucketInfo(name: bucket);

  @override
  Future<List<String>> listBucketOrder() async => const <String>[];

  @override
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String nextToken,
    int pageSize, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      forceRefreshCount++;
    }
    return ObjectListPage(items: <ObjectInfo>[directory], nextToken: '');
  }

  @override
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String taskId, {
    bool permanent = false,
  }) => _deleteCompleter.future;

  @override
  Future<List<CachedFileRecord>> removeCacheIndexPrefix({
    required String bucket,
    required String objectKeyPrefix,
  }) async => const <CachedFileRecord>[];

  void completeDelete() => _deleteCompleter.complete();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
