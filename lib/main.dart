import 'package:flutter/widgets.dart';
import 'package:remote_storage/app/remote_storage_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RemoteStorageApp());
}
