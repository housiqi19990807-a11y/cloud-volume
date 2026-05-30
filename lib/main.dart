import 'package:flutter/widgets.dart';
import 'package:remote_storage/platform/platform_bootstrap.dart';
import 'package:remote_storage/app/remote_storage_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePlatformServices();
  runApp(const RemoteStorageApp());
}
