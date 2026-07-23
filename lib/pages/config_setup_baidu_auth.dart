part of 'config_setup_page.dart';

// Baidu OAuth actions are isolated from the generic first-run form flow.
extension _ConfigSetupBaiduAuth on _ConfigSetupPageState {
  Future<void> _authorizeBaiduPan() async {
    final code = _baiduAuthCodeController.text.trim();
    if (code.isEmpty) {
      _updateState(() => _errorText = '请先粘贴百度授权页显示的授权码。');
      return;
    }
    _updateState(() => _authorizingBaidu = true);
    try {
      final config = await widget.api.authorizeBaiduPan(
        _nameController.text.trim(),
        code,
      );
      if (!mounted) return;
      _updateState(() {
        _authorizedBaiduConfig = config;
        _baiduAuthCodeController.clear();
        _errorText = null;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = config.displayName;
        }
      });
    } catch (error) {
      if (mounted) {
        _updateState(() => _errorText = describeBridgeError(error));
      }
    } finally {
      if (mounted) {
        _updateState(() => _authorizingBaidu = false);
      }
    }
  }

  Future<void> _startBaiduPanAuthorization() async {
    _updateState(() => _openingBaiduAuthPage = true);
    try {
      final authUrl = await widget.api.startBaiduPanAuthorization();
      if (!mounted) return;
      _updateState(() {
        _baiduAuthUrl = authUrl;
        _errorText = null;
      });
    } catch (error) {
      if (mounted) {
        _updateState(() => _errorText = describeBridgeError(error));
      }
    } finally {
      if (mounted) {
        _updateState(() => _openingBaiduAuthPage = false);
      }
    }
  }
}
