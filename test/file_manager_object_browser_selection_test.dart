// File manager object browser tests cover desktop selection gestures around the list header.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'header select-all toggles off instead of clearing then reselecting',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final objects = <ObjectInfo>[
        const ObjectInfo(key: 'photos/default.png', size: 1024, isDir: false),
        const ObjectInfo(key: 'photos/garage.png', size: 2048, isDir: false),
      ];
      final selectedKeys = <String>{};

      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) {
                void toggleSelection(ObjectInfo object) {
                  setState(() {
                    if (!selectedKeys.add(object.key)) {
                      selectedKeys.remove(object.key);
                    }
                  });
                }

                void toggleSelectAll() {
                  final keys = objects.map((object) => object.key).toSet();
                  final hasUnselected = keys.any(
                    (key) => !selectedKeys.contains(key),
                  );
                  setState(() {
                    if (hasUnselected) {
                      selectedKeys.addAll(keys);
                    } else {
                      selectedKeys.removeAll(keys);
                    }
                  });
                }

                return SizedBox(
                  width: 900,
                  height: 600,
                  child: FileManagerObjectBrowser(
                    objects: objects,
                    prefix: 'photos/',
                    isGrid: false,
                    scrollController: ScrollController(),
                    hasMore: false,
                    loadingMore: false,
                    selectedKeys: selectedKeys,
                    deletingKeys: const <String>{},
                    gridIconSize: 44,
                    listIconSize: 34,
                    onOpenDirectory: (_) {},
                    onOpenFile: (_) {},
                    onDownloadFile: (_) {},
                    onNavigateUp: () {},
                    onToggleSelection: toggleSelection,
                    onSelectionSetChanged: (keys) {
                      setState(() {
                        selectedKeys
                          ..clear()
                          ..addAll(keys);
                      });
                    },
                    onToggleSelectAll: toggleSelectAll,
                    onClearSelection: () {
                      setState(selectedKeys.clear);
                    },
                    onObjectAction: (_, _) {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final headerControl = find.byType(ListSelectionControl).first;

      await tester.tap(headerControl, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(selectedKeys, containsAll(objects.map((object) => object.key)));

      await tester.tap(headerControl, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(selectedKeys, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('clicking a directory in selection mode toggles selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final objects = <ObjectInfo>[
      const ObjectInfo(key: 'photos/default.png', size: 1024, isDir: false),
      const ObjectInfo(key: 'photos/album/', size: 0, isDir: true),
    ];
    final selectedKeys = <String>{'photos/default.png'};
    var openedDirectoryCount = 0;

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              void toggleSelection(ObjectInfo object) {
                setState(() {
                  if (!selectedKeys.add(object.key)) {
                    selectedKeys.remove(object.key);
                  }
                });
              }

              return SizedBox(
                width: 900,
                height: 600,
                child: FileManagerObjectBrowser(
                  objects: objects,
                  prefix: '',
                  isGrid: false,
                  scrollController: ScrollController(),
                  hasMore: false,
                  loadingMore: false,
                  selectedKeys: selectedKeys,
                  deletingKeys: const <String>{},
                  gridIconSize: 44,
                  listIconSize: 34,
                  onOpenDirectory: (_) => openedDirectoryCount++,
                  onOpenFile: (_) {},
                  onDownloadFile: (_) {},
                  onNavigateUp: () {},
                  onToggleSelection: toggleSelection,
                  onSelectionSetChanged: (keys) {
                    setState(() {
                      selectedKeys
                        ..clear()
                        ..addAll(keys);
                    });
                  },
                  onToggleSelectAll: () {},
                  onClearSelection: () {
                    setState(selectedKeys.clear);
                  },
                  onObjectAction: (_, _) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('album'), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(openedDirectoryCount, 0);
    expect(selectedKeys, contains('photos/album/'));

    await tester.tap(find.text('album'), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(openedDirectoryCount, 0);
    expect(selectedKeys, isNot(contains('photos/album/')));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
