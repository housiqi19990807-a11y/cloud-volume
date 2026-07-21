// Global trash header tests keep selection mode from resizing the page header.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/widgets/global_trash_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('selection actions keep the default header height', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(selectedCount: 0));
    final idleHeight = tester
        .getSize(find.byType(GlobalTrashHeaderActions))
        .height;

    await tester.pumpWidget(_testApp(selectedCount: 1));
    await tester.pump();
    final selectedHeight = tester
        .getSize(find.byType(GlobalTrashHeaderActions))
        .height;

    expect(selectedHeight, idleHeight);
    expect(selectedHeight, lessThan(50));
    expect(find.text('清空选择'), findsNothing);
  });
}

Widget _testApp({required int selectedCount}) {
  return ShadApp(
    home: Material(
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: 360,
          child: GlobalTrashHeaderActions(
            selectedCount: selectedCount,
            loading: false,
            onRefresh: () {},
            onRestoreSelected: () {},
            onDeleteSelected: () {},
            onClearTrash: () {},
          ),
        ),
      ),
    ),
  );
}
