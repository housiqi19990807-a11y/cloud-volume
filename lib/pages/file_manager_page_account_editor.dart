part of 'file_manager_page.dart';

// Account recovery opens the existing in-app editor instead of the first-run setup page.
extension _FileManagerPageAccountEditor on _FileManagerPageState {
  Future<void> _showFailedAccountEditor() async {
    final profileName = _accountEditorProfileName();
    try {
      final config = widget.profiles.isEmpty
          ? widget.config
          : await widget.api.loadProfile(profileName);
      if (!mounted) return;
      await showAccountEditor(
        context: context,
        api: widget.api,
        initialConfig: config,
        profileName: profileName,
        editing: true,
        onSaved: widget.onRefresh,
        onSave: (updated) => _saveRecoveredAccount(profileName, updated),
      );
    } catch (error) {
      if (!mounted) return;
      showAppErrorToast(context, message: describeBridgeError(error));
    }
  }

  String _accountEditorProfileName() {
    final failed = _failedBucketProfileName?.trim() ?? '';
    if (failed.isNotEmpty) return failed;
    for (final profile in widget.profiles) {
      if (profile.active) return profile.name;
    }
    return widget.profiles.isEmpty ? 'default' : widget.profiles.first.name;
  }

  Future<bool> _saveRecoveredAccount(
    String profileName,
    RemoteStorageConfig config,
  ) async {
    if (!config.isConfigured) {
      showAppErrorToast(context, message: '请补全账号连接信息。');
      return false;
    }
    try {
      await widget.api.saveProfile(profileName, config);
      if (!mounted) return false;
      showAppToast(context, title: '账号已更新', message: config.displayName);
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, message: describeBridgeError(error));
      }
      return false;
    }
  }
}
