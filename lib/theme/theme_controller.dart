// Theme controller: manages the current accent preset with persistence.
// Wraps InheritedWidget so descendants can read/write the accent.

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAccentKey = 'remote_storage_accent_preset';

class ThemeController extends InheritedWidget {
  const ThemeController({
    super.key,
    required this.accent,
    required this.onAccentChanged,
    required super.child,
  });

  final AccentPreset accent;
  final ValueChanged<AccentPreset> onAccentChanged;

  static ThemeController of(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<ThemeController>();
    assert(controller != null, 'No ThemeController found in widget tree');
    return controller!;
  }

  @override
  bool updateShouldNotify(ThemeController oldWidget) =>
      accent != oldWidget.accent;
}

/// Widget that loads the saved accent from preferences and provides
/// a [ThemeController] to the subtree.
class ThemeControllerScope extends StatefulWidget {
  const ThemeControllerScope({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    AccentPreset accent,
    ValueChanged<AccentPreset> onChange,
  )
  builder;

  @override
  State<ThemeControllerScope> createState() => _ThemeControllerScopeState();

  /// Convenience static to load saved accent (or default).
  static Future<AccentPreset> loadSavedAccent() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kAccentKey);
    if (name == null) return AccentPreset.blue;
    return AccentPreset.values.cast<AccentPreset?>().firstWhere(
      (e) => e?.name == name,
      orElse: () => AccentPreset.blue,
    )!;
  }

  static Future<void> _saveAccent(AccentPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccentKey, preset.name);
  }
}

class _ThemeControllerScopeState extends State<ThemeControllerScope> {
  late AccentPreset _accent;

  void _onAccentChanged(AccentPreset preset) {
    setState(() => _accent = preset);
    ThemeControllerScope._saveAccent(preset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _accent, _onAccentChanged);
  }

  // The accent is set via the builder callback from the parent which
  // does the async load. We keep _accent in sync through the callback.
}

/// Standalone initializer that loads persisted accent, then builds the tree.
class ThemeInitializer extends StatefulWidget {
  const ThemeInitializer({super.key, required this.child});

  final Widget child;

  @override
  State<ThemeInitializer> createState() => _ThemeInitializerState();
}

class _ThemeInitializerState extends State<ThemeInitializer> {
  AccentPreset _accent = AccentPreset.blue;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAccent();
  }

  Future<void> _loadAccent() async {
    final saved = await ThemeControllerScope.loadSavedAccent();
    if (!mounted) return;
    setState(() {
      _accent = saved;
      _loaded = true;
    });
  }

  void _onAccentChanged(AccentPreset preset) {
    setState(() => _accent = preset);
    ThemeControllerScope._saveAccent(preset);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(color: Color(0xfff8fafc)),
      );
    }
    return ThemeController(
      accent: _accent,
      onAccentChanged: _onAccentChanged,
      child: widget.child,
    );
  }
}
