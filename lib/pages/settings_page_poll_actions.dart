part of 'settings_page.dart';

// P0 remote-poll persistence stays separate from the general settings actions.
extension _SettingsPagePollActions on _SettingsPageState {
  Future<void> _saveMountRemotePollInterval(
    RemoteStorageConfig config,
    int seconds,
  ) async {
    if (seconds == config.effectiveMountRemotePollSeconds) {
      return;
    }
    _updateState(() {
      _savingMountRemotePollInterval = true;
      _mountRemotePollIntervalError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(mountRemotePollSeconds: seconds),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (mounted) {
        _updateState(() => _mountRemotePollIntervalError = error.toString());
      }
    } finally {
      if (mounted) {
        _updateState(() => _savingMountRemotePollInterval = false);
      }
    }
  }
}
