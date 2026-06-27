// When a modal child is open, refocus the top child if the parent window is clicked.

import 'package:flutter/material.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:window_manager/window_manager.dart';

class DesktopModalParentFocusRelay extends StatefulWidget {
  const DesktopModalParentFocusRelay({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopModalParentFocusRelay> createState() =>
      _DesktopModalParentFocusRelayState();
}

class _DesktopModalParentFocusRelayState extends State<DesktopModalParentFocusRelay>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    reconcileModalOverlayWithOpenChildren().then((_) {
      if (!DesktopModalOverlayController.instance.visible) return;
      bringTopModalChildToFront();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
