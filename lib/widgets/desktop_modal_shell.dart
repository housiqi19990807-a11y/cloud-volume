// Shared title bar for desktop modal sub-windows. Replaces the per-window
// _AccountEditorTitleBar / _SyncEditorTitleBar / _PickerTitleBar copies.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 44px title bar with title text and a close button.
///
/// Used by every modal sub-window (account editor, sync editor, directory
/// picker) so they share identical chrome. The [onClose] callback is
/// responsible for the full close sequence (overlay release + window close).
class DesktopModalShell extends StatelessWidget {
  const DesktopModalShell({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
