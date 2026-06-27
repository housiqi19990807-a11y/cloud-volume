// Modal sub-windows stay always-on-top only while they hold focus (not over other apps).

import 'package:flutter/material.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:window_manager/window_manager.dart';

class DesktopModalWindowFocusGate extends StatefulWidget {
  const DesktopModalWindowFocusGate({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopModalWindowFocusGate> createState() =>
      _DesktopModalWindowFocusGateState();
}

class _DesktopModalWindowFocusGateState extends State<DesktopModalWindowFocusGate>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAlwaysOnTop());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncAlwaysOnTop() async {
    try {
      final focused = await windowManager.isFocused();
      if (focused) {
        await applyModalChildWindowChrome();
      } else {
        await clearModalChildWindowChrome();
      }
    } catch (_) {}
  }

  @override
  void onWindowFocus() {
    _syncAlwaysOnTop();
  }

  @override
  void onWindowBlur() {
    clearAlwaysOnTopForAllModalChildren();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
