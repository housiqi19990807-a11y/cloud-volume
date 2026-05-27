// App theme: tech-blue default with user-customizable accent color.
// Uses ShadBlueColorScheme as base, overrides primary/ring/selection per preset.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String kAppFontFamily = 'SourceHanSansCN';

/// Named accent presets the user can pick from.
enum AccentPreset {
  blue('科技蓝', Color(0xff2563eb)),
  violet('紫罗兰', Color(0xff7c3aed)),
  green('翡翠绿', Color(0xff16a34a)),
  orange('活力橙', Color(0xffea580c)),
  rose('玫瑰红', Color(0xffe11d48));

  const AccentPreset(this.label, this.color);
  final String label;
  final Color color;
}

/// Derives a lighter tint from [source] for selection highlights.
Color _lighten(Color source) {
  return Color.fromARGB(
    255,
    (source.r * 255 + (1 - source.r) * 255 * 0.7).round().clamp(0, 255),
    (source.g * 255 + (1 - source.g) * 255 * 0.7).round().clamp(0, 255),
    (source.b * 255 + (1 - source.b) * 255 * 0.7).round().clamp(0, 255),
  );
}

/// Builds ShadThemeData with the given accent baked into the color scheme.
ShadThemeData buildAppTheme(AccentPreset preset) {
  final base = ShadBlueColorScheme.light();
  final c = preset.color;
  final scheme = base.copyWith(
    primary: c,
    ring: c,
    selection: _lighten(c),
    accent: c.withValues(alpha: 0.08),
    secondary: c.withValues(alpha: 0.06),
  );
  return ShadThemeData(
    colorScheme: scheme,
    brightness: Brightness.light,
    textTheme: ShadTextTheme(family: kAppFontFamily),
  );
}

/// Dark variant for future use.
ShadThemeData buildAppThemeDark(AccentPreset preset) {
  final base = ShadBlueColorScheme.dark();
  final c = preset.color;
  final scheme = base.copyWith(primary: c, ring: c, selection: _lighten(c));
  return ShadThemeData(
    colorScheme: scheme,
    brightness: Brightness.dark,
    textTheme: ShadTextTheme(family: kAppFontFamily),
  );
}
