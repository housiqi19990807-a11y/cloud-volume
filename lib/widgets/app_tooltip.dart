// App tooltip wraps shadcn_ui tooltip usage so transient hints stay visually consistent.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShadTooltip(builder: (context) => Text(message), child: child);
  }
}
