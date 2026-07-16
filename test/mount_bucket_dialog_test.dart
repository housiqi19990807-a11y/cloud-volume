// Mount dialog tests cover Windows presentation and access-mode selections.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/mount_bucket_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('defaults to an available drive letter on Windows', (
    tester,
  ) async {
    MountBucketOptions? selected;
    await _openDialog(
      tester,
      onSelected: (value) => selected = value,
      showWindowsMountMode: true,
      availableDriveLetters: const <String>['Z:', 'Y:'],
    );

    expect(find.text('只读挂载'), findsOneWidget);
    expect(find.text('挂载模式'), findsOneWidget);
    expect(find.text('分配盘符'), findsOneWidget);
    expect(find.text('盘符'), findsOneWidget);
    expect(find.text('Z:'), findsOneWidget);
    expect(find.text('挂载路径'), findsNothing);

    await tester.tap(find.byType(ShadSwitch));
    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.readOnly, isTrue);
    expect(selected!.driveLetter, 'Z:');
    expect(selected!.mountPath, isEmpty);
    expect(selected!.toJson()['driveLetter'], 'Z:');
  });

  testWidgets('lets the user select a different available drive letter', (
    tester,
  ) async {
    MountBucketOptions? selected;
    await _openDialog(
      tester,
      onSelected: (value) => selected = value,
      showWindowsMountMode: true,
      availableDriveLetters: const <String>['Z:', 'Y:'],
    );

    await tester.tap(find.text('Z:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Y:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected?.driveLetter, 'Y:');
  });

  testWidgets('switches from the default drive mode to path mode', (
    tester,
  ) async {
    MountBucketOptions? selected;
    await _openDialog(
      tester,
      onSelected: (value) => selected = value,
      showWindowsMountMode: true,
      availableDriveLetters: const <String>['Z:', 'Y:'],
    );

    await tester.tap(find.text('分配盘符'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('路径挂载'));
    await tester.pumpAndSettle();

    expect(find.text('挂载路径'), findsOneWidget);
    expect(find.text('盘符'), findsNothing);

    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();
    expect(selected?.driveLetter, isEmpty);
  });

  testWidgets('falls back to path mode when no drive letter is free', (
    tester,
  ) async {
    await _openDialog(tester, onSelected: (_) {}, showWindowsMountMode: true);

    expect(find.text('路径挂载'), findsOneWidget);
    expect(find.text('当前没有可分配的盘符，请使用路径挂载。'), findsOneWidget);
    expect(find.text('挂载路径'), findsOneWidget);
    expect(find.text('盘符'), findsNothing);
  });

  testWidgets('non-Windows dialog keeps the path-only presentation', (
    tester,
  ) async {
    await _openDialog(tester, onSelected: (_) {});

    expect(find.text('只读挂载'), findsOneWidget);
    expect(find.text('挂载模式'), findsNothing);
    expect(find.text('挂载路径'), findsOneWidget);
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  required ValueChanged<MountBucketOptions?> onSelected,
  bool showWindowsMountMode = false,
  List<String> availableDriveLetters = const <String>[],
}) async {
  await tester.pumpWidget(
    ShadApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ShadButton(
            onPressed: () async {
              onSelected(
                await showMountBucketDialog(
                  context,
                  bucket: 'bucket-a',
                  showWindowsMountMode: showWindowsMountMode,
                  availableDriveLetters: availableDriveLetters,
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
