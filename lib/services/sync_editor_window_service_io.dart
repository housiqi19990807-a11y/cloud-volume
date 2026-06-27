// Desktop sync-editor sub-window service opens an ad-hoc editor as a
// standalone OS window with its own Flutter engine and bridge connection.
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';

class SyncEditorWindowService {
  SyncEditorWindowService._();

  static final SyncEditorWindowService instance = SyncEditorWindowService._();

  bool get isSupported => true;

  Future<bool> openEditor({
    required List<String> profileNames,
    Map<String, dynamic>? initialProfile,
  }) async {
    final args = SyncEditorWindowArgs(
      profileNames: profileNames,
      initialProfileJson: initialProfile,
    );
    await WindowController.create(
      WindowConfiguration(arguments: args.toArguments()),
    );
    return true;
  }
}
