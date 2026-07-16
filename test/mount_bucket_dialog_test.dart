// Mount dialog tests cover optional Windows Cloud Files drive-letter requests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/mount_bucket_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('returns drive-letter request when the switch is selected', (
    tester,
  ) async {
    MountBucketOptions? selected;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShadButton(
              onPressed: () async {
                selected = await showMountBucketDialog(
                  context,
                  bucket: 'bucket-a',
                  allowDriveLetter: true,
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
    expect(find.text('分配盘符'), findsOneWidget);

    await tester.tap(find.byType(ShadSwitch));
    await tester.pump();
    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.assignDriveLetter, isTrue);
    expect(selected!.toJson()['assignDriveLetter'], isTrue);
  });

  testWidgets('hides the drive-letter switch when it is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShadButton(
              onPressed: () =>
                  showMountBucketDialog(context, bucket: 'bucket-a'),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('分配盘符'), findsNothing);
  });
}
