// Shared title bar for desktop modal sub-windows. Replaces the per-window
// _AccountEditorTitleBar / _SyncEditorTitleBar / _PickerTitleBar copies.

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
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

/// Hover-aware close button without Material ripple.
///
/// Hover only adds a neutral background wash — icon color stays fixed so the
/// control does not "re-skin" under the pointer (AGENTS.md Hover visual style).
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
    final interaction = ListInteractionColors.fromTheme(theme);
    // Icon color is stable; only background wash reacts to hover.
    final iconColor = theme.colorScheme.mutedForeground;
    final background = interaction.rowBackground(
      selected: false,
      hovered: _hovered,
      pressed: false,
    );
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
            child: Icon(Icons.close, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}
