// Grey modal barrier on the parent window while a child OS window is shown.

import 'package:flutter/material.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';

class DesktopModalScrim extends StatefulWidget {
  const DesktopModalScrim({super.key});

  @override
  State<DesktopModalScrim> createState() => _DesktopModalScrimState();
}

class _DesktopModalScrimState extends State<DesktopModalScrim> {
  @override
  void initState() {
    super.initState();
    DesktopModalOverlayController.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    DesktopModalOverlayController.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopModalOverlayController.instance.visible) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
