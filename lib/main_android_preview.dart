// Android UI preview entry: reuses the production app shell with mock data.

import 'package:flutter/widgets.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/services/ui_preview_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await createUiPreviewApi();
  runApp(RemoteStorageApp(apiFactory: () async => api, previewMode: true));
}
