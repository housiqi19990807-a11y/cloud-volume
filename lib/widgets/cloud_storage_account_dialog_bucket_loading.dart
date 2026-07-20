// ignore_for_file: library_private_types_in_public_api
part of 'cloud_storage_account_dialog.dart';

// Builds and validates the connection draft before entering bucket settings.
extension _AccountBucketLoading on _CloudStorageAccountDialogState {
  RemoteStorageConfig _draftConfig() {
    return buildAccountConfig(
      CloudStorageAccountDraft(
        storageType: _storageType,
        name: _nameController.text.trim(),
        mappedBucketName: _mappedBucketNameController.text.trim(),
        endpoint: _endpointController.text,
        region: _regionController.text,
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
        usePathStyle: _usePathStyle,
        webdavUsername: _webdavUsernameController.text,
        webdavPassword: _webdavPasswordController.text,
        proxyMode: _proxyMode,
        proxyType: _proxyType,
        proxyHost: _proxyHostController.text.trim(),
        proxyPort: _proxyPortController.text.trim(),
        proxyUsername: _proxyUsernameController.text.trim(),
        proxyPassword: _proxyPasswordController.text,
        bucketViews: _bucketViews,
      ),
      existing: widget.initialConfig,
      authorizedBaiduConfig: _authorizedBaiduConfig,
    );
  }

  Future<void> _loadBucketsForVisibility() async {
    markDirty(() {
      _loadingBuckets = true;
      _errorText = null;
    });
    try {
      final config = _draftConfig();
      if (!config.isConfigured) {
        throw StateError('请先完成连接信息或 OAuth 授权。');
      }
      final buckets = await widget.onListBuckets(config);
      if (!mounted) return;
      markDirty(() {
        _availableBuckets = buckets;
        _step = 2;
        _loadingBuckets = false;
      });
    } catch (error) {
      if (!mounted) return;
      markDirty(() {
        _loadingBuckets = false;
        _errorText = '无法读取桶列表：$error';
      });
    }
  }
}
