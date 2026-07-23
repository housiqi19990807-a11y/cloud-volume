// Mount dialog tests cover Windows presentation and access-mode selections.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
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
    expect(find.text('映射盘符只是将本地同步目录映射到盘符入口，不代表云存储的真实容量。'), findsOneWidget);

    final driveSelect = tester.widget<ShadSelect<String>>(
      find.byType(ShadSelect<String>),
    );
    expect(driveSelect.ensureSelectedVisible, isFalse);

    await tester.tap(find.byType(ShadSwitch));
    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.readOnly, isTrue);
    expect(selected!.driveLetter, 'Z:');
    expect(selected!.mountPath, isEmpty);
    expect(selected!.windowsMountEngine, WindowsMountEngine.winFsp);
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

  testWidgets('enforces a bucket read-only policy through WinFsp', (
    tester,
  ) async {
    MountBucketOptions? selected;
    await _openDialog(
      tester,
      onSelected: (value) => selected = value,
      showWindowsMountMode: true,
      availableDriveLetters: const <String>['Z:'],
      forceReadOnly: true,
    );

    expect(find.text('该桶已由账号策略设为只读，不能在此修改。'), findsOneWidget);
    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected?.readOnly, isTrue);
    expect(selected?.windowsMountEngine, WindowsMountEngine.winFsp);
  });

  testWidgets('offers managed Cloud Files cache cleanup at unmount', (
    tester,
  ) async {
    UnmountBucketChoice? selected;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShadButton(
              onPressed: () async {
                selected = await showUnmountBucketDialog(
                  context,
                  bucket: 'bucket-a',
                  canRemoveLocalCache: true,
                );
              },
              child: const Text('卸载'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('卸载'));
    await tester.pumpAndSettle();
    expect(find.text('同时删除本地缓存'), findsOneWidget);
    expect(
      find.text('请先关闭正在从该挂载目录打开的文件。卸载后仍打开的文件可能继续引用本地缓存，后续修改不会自动同步。'),
      findsOneWidget,
    );

    await tester.tap(find.byType(ShadSwitch));
    await tester.tap(find.text('确认卸载'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.removeLocalCache, isTrue);
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  required ValueChanged<MountBucketOptions?> onSelected,
  bool showWindowsMountMode = false,
  List<String> availableDriveLetters = const <String>[],
  bool forceReadOnly = false,
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
                  forceReadOnly: forceReadOnly,
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
