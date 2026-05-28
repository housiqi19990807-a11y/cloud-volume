// App toast helpers centralize shadcn_ui feedback so pages don't mix in Material snack bars.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void showAppToast(
  BuildContext context, {
  required String message,
  String? title,
}) {
  final toaster = ShadToaster.maybeOf(context);
  if (toaster == null) {
    return;
  }
  toaster.show(
    ShadToast(
      title: Text(title ?? message),
      description: title == null ? null : Text(message),
    ),
  );
}

void showAppErrorToast(
  BuildContext context, {
  required String message,
  String title = '操作失败',
}) {
  final toaster = ShadToaster.maybeOf(context);
  if (toaster == null) {
    return;
  }
  toaster.show(
    ShadToast.destructive(title: Text(title), description: Text(message)),
  );
}
