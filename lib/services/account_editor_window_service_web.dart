// Web fallback reports unsupported so callers can fall back to an in-app dialog.

class AccountEditorWindowService {
  AccountEditorWindowService._();

  static final AccountEditorWindowService instance = AccountEditorWindowService._();

  bool get isSupported => false;

  Future<bool> openEditor({
    Map<String, dynamic>? initialConfigJson,
    String? profileName,
    bool editing = false,
    required void Function() onSaved,
  }) async {
    return false;
  }
}
