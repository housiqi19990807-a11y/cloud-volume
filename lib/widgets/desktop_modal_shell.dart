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
          // Custom close control: no Material IconButton ink splash.
          _ModalShellCloseButton(onPressed: onClose),
        ],
      ),
    );
  }
}

/// Hover-aware close button without Material ripple (matches main-window
/// chrome controls more closely than [IconButton]).
class _ModalShellCloseButton extends StatefulWidget {
  const _ModalShellCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ModalShellCloseButton> createState() => _ModalShellCloseButtonState();
}

class _ModalShellCloseButtonState extends State<_ModalShellCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // Soft destructive wash on hover only — no primary blue ink splash.
    final background = _hovered
        ? const Color(0xfffef3f2)
        : Colors.transparent;
    final foreground =
        _hovered ? const Color(0xffb42318) : theme.colorScheme.mutedForeground;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: '关闭',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 36,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.close, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}
