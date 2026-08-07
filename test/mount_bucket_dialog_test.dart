// Mount dialog tests cover Windows presentation and access-mode selections.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/mount_bucket_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'Cloud Files uses a path instead of a capacity-misleading drive',
    (tester) async {
      MountBucketOptions? selected;
      await _openDialog(
        tester,
        onSelected: (value) => selected = value,
        showWindowsMountMode: true,
        availableDriveLetters: const <String>['Z:', 'Y:'],
      );

      expect(find.text('只读挂载'), findsOneWidget);
      expect(find.text('挂载路径'), findsOneWidget);
      expect(find.text('盘符'), findsNothing);
      expect(
        find.text(
          'Cloud Files 使用本地同步目录。需要在资源管理器显示桶级容量时，请选择 WinFsp 虚拟文件系统并分配盘符。',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('开始挂载'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.readOnly, isFalse);
      expect(selected!.driveLetter, isEmpty);
      expect(selected!.windowsMountEngine, WindowsMountEngine.cloudFiles);
    },
  );

  testWidgets('lets the user select a different available drive letter', (
    tester,
  ) async {
    MountBucketOptions? selected;
    await _openDialog(
      tester,
      onSelected: (value) => selected = value,
      showWindowsMountMode: true,
      availableDriveLetters: const <String>['Z:', 'Y:'],
      currentEngine: WindowsMountEngine.winFsp,
      winFspAvailable: true,
    );

    await tester.tap(find.text('Z:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Y:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected?.driveLetter, 'Y:');
  });

  testWidgets('Cloud Files stays path-based when no drive letter is free', (
    tester,
  ) async {
    await _openDialog(tester, onSelected: (_) {}, showWindowsMountMode: true);

    expect(find.text('挂载路径'), findsOneWidget);
    expect(find.text('盘符'), findsNothing);
  });

  testWidgets('WinFsp only offers drive-letter mounts', (tester) async {
    MountBucketOptions? selected;
    await _openDialog(
      tester,
      onSelected: (value) => selected = value,
      showWindowsMountMode: true,
      availableDriveLetters: const <String>['Z:', 'Y:'],
      currentEngine: WindowsMountEngine.winFsp,
      winFspAvailable: true,
    );

    expect(find.text('挂载模式'), findsNothing);
    expect(find.text('路径挂载'), findsNothing);
    expect(find.text('挂载路径'), findsNothing);
    expect(find.text('盘符'), findsOneWidget);

    await tester.tap(find.text('开始挂载'));
    await tester.pumpAndSettle();

    expect(selected?.mountPath, isEmpty);
    expect(selected?.driveLetter, 'Z:');
    expect(selected?.windowsMountEngine, WindowsMountEngine.winFsp);
  });

  testWidgets('blocks WinFsp mounts when no drive letter is free', (
    tester,
  ) async {
    await _openDialog(
      tester,
      onSelected: (_) {},
      showWindowsMountMode: true,
      currentEngine: WindowsMountEngine.winFsp,
      winFspAvailable: true,
    );

    expect(find.text('WinFsp 虚拟文件系统仅支持盘符挂载，请先释放一个可用盘符。'), findsOneWidget);
    final mountButton = tester.widget<ShadButton>(
      find.widgetWithText(ShadButton, '开始挂载'),
    );
    expect(mountButton.onPressed, isNull);
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
  WindowsMountEngine? currentEngine,
  bool winFspAvailable = false,
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
                  currentEngine: currentEngine,
                  winFspAvailable: winFspAvailable,
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
