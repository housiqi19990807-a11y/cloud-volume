import 'package:flutter/widgets.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(const RemoteStorageApp());
}
