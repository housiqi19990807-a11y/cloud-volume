// Unified in-app modal API. All business dialogs should enter through here
// instead of calling showShadDialog directly so barrier, width, and chrome
// stay consistent. OS sub-windows are a separate debug-only path.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Default max width for standard form / confirm modals.
const double kAppModalDefaultMaxWidth = 480;

/// Default content width used inside many existing dialogs.
const double kAppModalDefaultContentWidth = 420;

/// Presents an in-app modal route. Prefer this over bare [showShadDialog].
///
/// Pass a builder that returns a [ShadDialog] (or a widget that builds one)
/// so existing dual-mode editors (`asDialog: true`) keep working unchanged.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0xcc000000),
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  return showShadDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
  );
}

/// Convenience builder for title / description / body / trailing action row.
///
/// Use for simple confirmations and forms that do not already own a
/// [ShadDialog]. Large dual-mode editors should keep building their own
/// [ShadDialog] and call [showAppModal] instead.
Future<T?> showAppModalDialog<T>({
  required BuildContext context,
  Widget? title,
  Widget? description,
  Widget? child,
  List<Widget> actions = const [],
  double maxWidth = kAppModalDefaultMaxWidth,
  double? contentWidth,
  bool scrollable = false,
  bool barrierDismissible = true,
  bool alert = false,
  bool expandActionsWhenTiny = true,
}) {
  final effectiveContentWidth = contentWidth ??
      (maxWidth > 40 ? maxWidth - 40 : maxWidth).clamp(280.0, maxWidth);

  return showAppModal<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      Widget? body = child;
if (actions.isNotEmpty) {
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?child,
            if (child != null) const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  actions[i],
                ],
              ],
            ),
          ],
        );
      }

      final sizedBody =
          body == null ? null : SizedBox(width: effectiveContentWidth, child: body);

      final constraints = BoxConstraints(maxWidth: maxWidth);
      if (alert) {
        return ShadDialog.alert(
          title: title,
          description: description,
          constraints: constraints,
          scrollable: scrollable,
          expandActionsWhenTiny: expandActionsWhenTiny,
          child: sizedBody,
        );
      }
      return ShadDialog(
        title: title,
        description: description,
        constraints: constraints,
        scrollable: scrollable,
        expandActionsWhenTiny: expandActionsWhenTiny,
        child: sizedBody,
      );
    },
  );
}

/// Yes/no confirmation modal with cancel + confirm actions.
Future<bool?> showAppConfirmModal({
  required BuildContext context,
  required Widget title,
  Widget? description,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
  double maxWidth = 380,
  bool barrierDismissible = true,
}) {
  return showAppModalDialog<bool>(
    context: context,
    title: title,
    description: description,
    maxWidth: maxWidth,
    barrierDismissible: barrierDismissible,
    actions: [
      Builder(
        builder: (dialogContext) => ShadButton.outline(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
      ),
      Builder(
        builder: (dialogContext) {
          if (destructive) {
            return ShadButton.destructive(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            );
          }
          return ShadButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          );
        },
      ),
    ],
  );
}
