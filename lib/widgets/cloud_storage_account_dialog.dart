// 新增账号弹窗先选择存储类型，再展示对应认证字段。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageAccountDraft {
  const CloudStorageAccountDraft({
    required this.storageType,
    required this.name,
    required this.mappedBucketName,
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.usePathStyle,
    required this.webdavUsername,
    required this.webdavPassword,
  });

  final StorageType storageType;
  final String name;
  final String mappedBucketName;
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final bool usePathStyle;
  final String webdavUsername;
  final String webdavPassword;
}

class CloudStorageAccountDialog extends StatefulWidget {
  const CloudStorageAccountDialog({
    super.key,
    required this.onSave,
    this.initialConfig,
    this.editing = false,
  });

  final Future<bool> Function(CloudStorageAccountDraft draft) onSave;
  final RemoteStorageConfig? initialConfig;
  final bool editing;

  @override
  State<CloudStorageAccountDialog> createState() =>
      _CloudStorageAccountDialogState();
}

class _CloudStorageAccountDialogState extends State<CloudStorageAccountDialog> {
  StorageType _storageType = StorageType.s3;
  final _nameController = TextEditingController();
  final _mappedBucketNameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _regionController = TextEditingController(text: 'auto');
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _webdavUsernameController = TextEditingController();
  final _webdavPasswordController = TextEditingController();
  bool _mappedBucketNameEdited = false;
  bool _usePathStyle = true;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    if (config == null) return;
    _storageType = config.storageType;
    _nameController.text = config.displayName;
    _mappedBucketNameController.text = config.mappedBucketName;
    _endpointController.text = config.endpoint;
    _regionController.text = config.region.isEmpty ? 'auto' : config.region;
    _accessKeyController.text = config.accessKeyId;
    _webdavUsernameController.text = config.webdavUsername;
    _usePathStyle = config.usePathStyle;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mappedBucketNameController.dispose();
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
    final isWebDav = _storageType == StorageType.webdav;
    return ShadDialog(
      title: Text(widget.editing ? '编辑账号' : '新增账号'),
      description: Text(
        widget.editing ? '修改账号连接信息；密钥或密码留空则保留当前保存值。' : '先选择存储类型，再填写对应的连接信息。',
      ),
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
              placeholder: const Text('名称'),
              onChanged: (_) => _syncMappedBucketName(),
            ),
            if (isWebDav) ...[
              const SizedBox(height: 12),
              ShadInput(
                controller: _mappedBucketNameController,
                placeholder: const Text('映射桶名称，默认使用名称'),
                onChanged: (_) => _mappedBucketNameEdited = true,
              ),
            ],
            const SizedBox(height: 12),
            if (!isWebDav)
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
                ShadButton(
                  onPressed: _submit,
                  child: Text(widget.editing ? '保存修改' : '保存账号'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _s3Fields() {
    return [
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
        placeholder: Text(
          widget.editing ? '留空则保留当前 Secret Key' : 'Secret Access Key',
        ),
        obscureText: true,
      ),
      const SizedBox(height: 14),
      _S3AdvancedOptions(
        usePathStyle: _usePathStyle,
        onPathStyleChanged: (value) => setState(() => _usePathStyle = value),
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
        placeholder: Text(widget.editing ? '留空则保留当前 WebDAV 密码' : 'WebDAV 密码'),
        obscureText: true,
      ),
    ];
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final mappedBucketName = _storageType == StorageType.webdav
        ? (_mappedBucketNameController.text.trim().isEmpty
              ? name
              : _mappedBucketNameController.text)
        : _nameController.text;
    final saved = await widget.onSave(
      CloudStorageAccountDraft(
        storageType: _storageType,
        name: _nameController.text,
        mappedBucketName: mappedBucketName,
        endpoint: _endpointController.text,
        region: _regionController.text,
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
        usePathStyle: _usePathStyle,
        webdavUsername: _webdavUsernameController.text,
        webdavPassword: _webdavPasswordController.text,
      ),
    );
    if (saved && mounted) Navigator.of(context).pop();
  }

  void _syncMappedBucketName() {
    if (widget.editing || _mappedBucketNameEdited) {
      return;
    }
    _mappedBucketNameController.text = _nameController.text;
  }
}

class _S3AdvancedOptions extends StatelessWidget {
  const _S3AdvancedOptions({
    required this.usePathStyle,
    required this.onPathStyleChanged,
  });

  final bool usePathStyle;
  final ValueChanged<bool> onPathStyleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ShadSwitch(
        value: usePathStyle,
        onChanged: onPathStyleChanged,
        label: Text(
          '使用路径风格访问',
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
        sublabel: Text(
          '推荐用于 MinIO、私有 S3 和多数兼容对象存储。',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 12,
          ),
        ),
      ),
    );
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
