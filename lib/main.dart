import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:remote_storage/app/remote_storage_app.dart';

// main configures the native macOS window integration before bootstrapping Flutter UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isMacOS) {
    const config = MacosWindowUtilsConfig();
    await config.apply();
  }
  runApp(const RemoteStorageApp());
}
