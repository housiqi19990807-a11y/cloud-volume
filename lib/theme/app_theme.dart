// App theme defines a restrained macOS-native palette for the bootstrap flow.

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

MacosThemeData buildAppTheme() {
  return MacosThemeData.light().copyWith(
    primaryColor: const Color(0xFF226B74),
    canvasColor: const Color(0xFFF6F7F9),
    dividerColor: const Color(0xFFE1E5EA),
    accentColor: AccentColor.blue,
  );
}
