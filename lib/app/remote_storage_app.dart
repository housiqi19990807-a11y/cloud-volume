// The root app owns the macOS design system and bootstrap wiring.

import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:remote_storage/pages/app_bootstrap_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/theme/app_theme.dart';

class RemoteStorageApp extends StatelessWidget {
  const RemoteStorageApp({
    super.key,
    this.apiFactory = defaultRemoteStorageApiFactory,
  });

  final RemoteStorageApiFactory apiFactory;

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Remote Storage',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(),
      home: AppBootstrapPage(apiFactory: apiFactory),
    );
  }
}
