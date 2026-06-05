// 新增账号弹窗先选择存储类型，再展示对应认证字段。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageAccountDraft {
  const CloudStorageAccountDraft({
    required this.storageType,
    required this.provider,
    required this.name,
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.webdavUsername,
    required this.webdavPassword,
  });

  final StorageType storageType;
  final StorageProviderType provider;
  final String name;
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final String webdavUsername;
  final String webdavPassword;
}

class CloudStorageAccountDialog extends StatefulWidget {
  const CloudStorageAccountDialog({super.key, required this.onSave});

  final Future<bool> Function(CloudStorageAccountDraft draft) onSave;

  @override
  State<CloudStorageAccountDialog> createState() =>
      _CloudStorageAccountDialogState();
}

class _CloudStorageAccountDialogState extends State<CloudStorageAccountDialog> {
  StorageType _storageType = StorageType.s3;
  StorageProviderType _provider = StorageProviderType.s3;
  final _nameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _regionController = TextEditingController(text: 'auto');
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _webdavUsernameController = TextEditingController();
  final _webdavPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('新增账号'),
      description: const Text('先选择存储类型，再填写对应的连接信息。'),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StorageTypeSegmentedControl(
              value: _storageType,
              onChanged: (value) => setState(() => _storageType = value),
            ),
            const SizedBox(height: 12),
            ShadInput(
              controller: _nameController,
              placeholder: const Text('账号名称'),
            ),
            const SizedBox(height: 12),
            if (_storageType == StorageType.s3)
              ..._s3Fields()
            else
              ..._webdavFields(),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                ShadButton(onPressed: _submit, child: const Text('保存账号')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _s3Fields() {
    return [
      _S3ProviderSegmentedControl(
        value: _provider,
        onChanged: (value) => setState(() => _provider = value),
      ),
      const SizedBox(height: 12),
      ShadInput(
        controller: _endpointController,
        placeholder: const Text('https://s3.example.com'),
      ),
      const SizedBox(height: 12),
      ShadInput(
        controller: _regionController,
        placeholder: const Text('Region，例如 auto'),
      ),
      const SizedBox(height: 12),
      ShadInput(
        controller: _accessKeyController,
        placeholder: const Text('Access Key ID'),
      ),
      const SizedBox(height: 12),
      ShadInput(
        controller: _secretKeyController,
        placeholder: const Text('Secret Access Key'),
        obscureText: true,
      ),
    ];
  }

  List<Widget> _webdavFields() {
    return [
      ShadInput(
        controller: _endpointController,
        placeholder: const Text(
          'https://dav.example.com/remote.php/dav/files/me',
        ),
      ),
      const SizedBox(height: 12),
      ShadInput(
        controller: _webdavUsernameController,
        placeholder: const Text('WebDAV 用户名'),
      ),
      const SizedBox(height: 12),
      ShadInput(
        controller: _webdavPasswordController,
        placeholder: const Text('WebDAV 密码'),
        obscureText: true,
      ),
    ];
  }

  Future<void> _submit() async {
    final saved = await widget.onSave(
      CloudStorageAccountDraft(
        storageType: _storageType,
        provider: _provider,
        name: _nameController.text,
        endpoint: _endpointController.text,
        region: _regionController.text,
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
        webdavUsername: _webdavUsernameController.text,
        webdavPassword: _webdavPasswordController.text,
      ),
    );
    if (saved && mounted) Navigator.of(context).pop();
  }
}

class _StorageTypeSegmentedControl extends StatelessWidget {
  const _StorageTypeSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  final StorageType value;
  final ValueChanged<StorageType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        for (final item in StorageType.values) ...[
          Expanded(
            child: ShadButton(
              size: ShadButtonSize.sm,
              onPressed: () => onChanged(item),
              backgroundColor: item == value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
              foregroundColor: item == value
                  ? theme.colorScheme.primaryForeground
                  : theme.colorScheme.foreground,
              child: Text(item.label),
            ),
          ),
          if (item != StorageType.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _S3ProviderSegmentedControl extends StatelessWidget {
  const _S3ProviderSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  final StorageProviderType value;
  final ValueChanged<StorageProviderType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in StorageProviderType.values)
          SizedBox(
            height: 36,
            child: ShadButton(
              size: ShadButtonSize.sm,
              onPressed: () => onChanged(item),
              backgroundColor: item == value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
              foregroundColor: item == value
                  ? theme.colorScheme.primaryForeground
                  : theme.colorScheme.foreground,
              child: Text(item.label),
            ),
          ),
      ],
    );
  }
}
