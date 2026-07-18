// Bucket quota tests cover JSON compatibility, settings input, and list display.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/bucket_settings_dialog.dart';
import 'package:remote_storage/widgets/file_manager_bucket_browser.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const int _gibibyte = 1024 * 1024 * 1024;

void main() {
  test('bucket settings parse legacy and custom quota JSON', () {
    final legacy = BucketSettings.fromJson(const <String, dynamic>{});
    final configured = BucketSettings.fromJson(const <String, dynamic>{
      'custom_quota_bytes': 2 * _gibibyte,
    });
    final negative = BucketSettings.fromJson(const <String, dynamic>{
      'customQuotaBytes': -1,
    });

    expect(legacy.customQuotaBytes, 0);
    expect(configured.customQuotaBytes, 2 * _gibibyte);
    expect(configured.toJson()['customQuotaBytes'], 2 * _gibibyte);
    expect(negative.customQuotaBytes, 0);
    expect(negative.toJson().containsKey('customQuotaBytes'), isFalse);
    expect(formatBytes(1536 * _gibibyte), '1.5 TB');
  });

  test('bucket info parses provider quota fields', () {
    final bucket = BucketInfo.fromJson(const <String, dynamic>{
      'name': 'remote-root',
      'quotaBytes': 20 * _gibibyte,
      'usedBytes': 7 * _gibibyte,
    });

    expect(bucket.quotaBytes, 20 * _gibibyte);
    expect(bucket.usedBytes, 7 * _gibibyte);
  });

  testWidgets('bucket settings saves a decimal GB quota', (tester) async {
    RemoteStorageConfig? selected;
    await _openSettings(tester, onSelected: (value) => selected = value);

    await tester.enterText(find.byType(ShadInput).first, '1.5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(
      selected!.bucketSettingsFor('bucket-a').customQuotaBytes,
      (1.5 * _gibibyte).round(),
    );
  });

  testWidgets('bucket settings rejects malformed quota input', (tester) async {
    RemoteStorageConfig? selected;
    await _openSettings(tester, onSelected: (value) => selected = value);

    await tester.enterText(find.byType(ShadInput).first, '1.2.3');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(selected, isNull);
    expect(find.textContaining('请输入 0 到'), findsOneWidget);
    expect(find.text('桶设置'), findsOneWidget);
  });

  testWidgets('bucket list shows custom, provider, and unset quota values', (
    tester,
  ) async {
    final configured = RemoteStorageConfig.empty().copyWith(
      bucketSettings: const <String, BucketSettings>{
        'bucket-a': BucketSettings(
          readOnly: false,
          trashEnabled: true,
          trashDirectory: '.trash',
          customQuotaBytes: 1536 * _gibibyte,
        ),
      },
    );
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            height: 500,
            child: FileManagerBucketBrowser(
              buckets: <FileManagerBucketEntry>[
                _entry('bucket-a', configured),
                _entry('bucket-b', configured, quotaBytes: 20 * _gibibyte),
                _entry('bucket-c', configured),
              ],
              isGrid: false,
              gridIconSize: 56,
              listIconSize: 24,
              onOpenBucket: (_) {},
              mountStatuses: const <String, BucketMountStatus>{},
              busyBuckets: const <String>{},
              showActionColumn: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('配额'), findsOneWidget);
    expect(find.text('1.5 TB'), findsOneWidget);
    expect(find.text('20.0 GB'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });
}

Future<void> _openSettings(
  WidgetTester tester, {
  required ValueChanged<RemoteStorageConfig?> onSelected,
}) async {
  await tester.pumpWidget(
    ShadApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ShadButton(
            onPressed: () async {
              onSelected(
                await showBucketSettingsDialog(
                  context,
                  bucket: 'bucket-a',
                  config: RemoteStorageConfig.empty(),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

FileManagerBucketEntry _entry(
  String bucket,
  RemoteStorageConfig config, {
  int quotaBytes = 0,
}) {
  return FileManagerBucketEntry.fromBucketInfo(
    bucket: BucketInfo(name: bucket, quotaBytes: quotaBytes),
    profileName: 'profile-a',
    sourceLabel: '账号 A',
    config: config,
  );
}
