part of 'settings_page.dart';

// Windows mount engine / WinFsp install actions live in their own part file so
// the main settings actions extension stays under the 500-line limit.
extension _SettingsPageWindowsMountActions on _SettingsPageState {
  Future<void> _saveWindowsMountEngine(
    RemoteStorageConfig config,
    WindowsMountEngine engine,
  ) async {
    if (engine == config.windowsMountEngine) return;
    await _saveWindowsMountAdvancedConfig(
      config.copyWith(windowsMountEngine: engine),
    );
  }

  Future<void> _saveWindowsWinFspCapacity(
    RemoteStorageConfig config,
    int capacityGb,
  ) async {
    if (capacityGb <= 0) {
      _updateState(() => _windowsMountEngineError = '虚拟总容量必须大于 0 GB。');
      return;
    }
    if (capacityGb == config.windowsWinFspCapacityGb) return;
    await _saveWindowsMountAdvancedConfig(
      config.copyWith(windowsWinFspCapacityGb: capacityGb),
    );
  }

  Future<void> _installWindowsWinFsp() async {
    if (widget.api is! WindowsWinFspQuery) {
      _updateState(() => _windowsMountEngineError = '当前运行环境不支持安装 WinFsp。');
      return;
    }
    _updateState(() {
      _installingWindowsWinFsp = true;
      _windowsMountEngineError = null;
    });
    try {
      final available =
          await (widget.api as WindowsWinFspQuery).installWindowsWinFsp();
      if (!mounted) return;
      _updateState(() {
        _winFspAvailable = available;
        _installingWindowsWinFsp = false;
      });
      if (available) {
        showAppToast(
          context,
          title: 'WinFsp 已安装',
          message: '现在可以在高级设置中选择 WinFsp 虚拟文件系统引擎。',
        );
      } else {
        _updateState(
          () => _windowsMountEngineError = 'WinFsp 安装完成但驱动仍不可见，可能需要重启后再试。',
        );
      }
    } catch (error) {
      if (!mounted) return;
      _updateState(() {
        _installingWindowsWinFsp = false;
        _windowsMountEngineError = error.toString();
      });
      showAppErrorToast(context, title: '安装 WinFsp 失败', message: error.toString());
    }
  }

  Future<void> _saveWindowsMountAdvancedConfig(
    RemoteStorageConfig config,
  ) async {
    _updateState(() {
      _savingWindowsMountEngine = true;
      _windowsMountEngineError = null;
    });
    try {
      await widget.api.saveConfig(config);
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _windowsMountEngineError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingWindowsMountEngine = false);
      }
    }
  }
}

