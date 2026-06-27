// Web fallback reports unsupported so callers can fall back to an in-app editor.

class SyncEditorWindowService {
  SyncEditorWindowService._();

  static final SyncEditorWindowService instance = SyncEditorWindowService._();

  bool get isSupported => false;

  Future<bool> openEditor({
    required List<String> profileNames,
    Map<String, dynamic>? initialProfile,
  }) async {
    return false;
  }
}
