part of 'cloud_storage_account_dialog.dart';

// Edited S3 credentials are verified explicitly before the account is saved.
extension _AccountCredentialValidation on _CloudStorageAccountDialogState {
  void _syncMappedBucketName() {
    if (widget.editing || _mappedBucketNameEdited) return;
    _mappedBucketNameController.text = _nameController.text;
  }

  bool get _shouldShowCredentialValidation =>
      widget.editing &&
      _storageType == StorageType.s3 &&
      (_accessKeyController.text.trim() != _initialAccessKey ||
          _secretKeyController.text.trim().isNotEmpty);

  void _onCredentialInputChanged() {
    if (!widget.editing || !mounted) return;
    markDirty(() {
      _credentialsValidated = false;
      _credentialValidationText = null;
    });
  }

  Future<void> _validateCredentials() async {
    markDirty(() {
      _validatingCredentials = true;
      _credentialsValidated = false;
      _credentialValidationText = null;
    });
    try {
      await widget.api.validateAccountCredentials(_draftConfig());
      if (!mounted) return;
      markDirty(() {
        _credentialsValidated = true;
        _credentialValidationText = '鉴权成功，保存后会替换当前账号凭证。';
      });
    } catch (error) {
      if (!mounted) return;
      markDirty(() => _credentialValidationText = describeBridgeError(error));
    } finally {
      if (mounted) markDirty(() => _validatingCredentials = false);
    }
  }

  Widget _buildCredentialValidationControl() {
    if (!_shouldShowCredentialValidation) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        ShadButton.outline(
          onPressed: _validatingCredentials ? null : _validateCredentials,
          child: Text(_validatingCredentials ? '正在验证...' : '验证修改后的凭证'),
        ),
        if (_credentialValidationText != null) ...[
          const SizedBox(height: 8),
          Text(
            _credentialValidationText!,
            style: TextStyle(
              fontSize: 12,
              color: _credentialsValidated
                  ? theme.colorScheme.primary
                  : theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}
