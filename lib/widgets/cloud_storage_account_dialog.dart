// 新增云存储账号弹窗使用固定分段按钮，避免下拉浮层影响页面布局。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageAccountDraft {
  const CloudStorageAccountDraft({
    required this.provider,
    required this.name,
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
  });

  final StorageProviderType provider;
  final String name;
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
}

class CloudStorageAccountDialog extends StatefulWidget {
  const CloudStorageAccountDialog({
    super.key,
    required this.initialProvider,
    required this.onSave,
  });

  final StorageProviderType initialProvider;
  final Future<bool> Function(CloudStorageAccountDraft draft) onSave;

  @override
  State<CloudStorageAccountDialog> createState() =>
      _CloudStorageAccountDialogState();
}

class _CloudStorageAccountDialogState extends State<CloudStorageAccountDialog> {
  late StorageProviderType _provider = widget.initialProvider;
  final _nameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _regionController = TextEditingController(text: 'auto');
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('新增云存储账号'),
      description: const Text('保存后会出现在对应上游类型的账号列表里。'),
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProviderSegmentedControl(
              value: _provider,
              onChanged: (value) => setState(() => _provider = value),
            ),
            const SizedBox(height: 12),
            ShadInput(
              controller: _nameController,
              placeholder: const Text('账号名称'),
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

  Future<void> _submit() async {
    final saved = await widget.onSave(
      CloudStorageAccountDraft(
        provider: _provider,
        name: _nameController.text,
        endpoint: _endpointController.text,
        region: _regionController.text,
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
      ),
    );
    if (saved && mounted) Navigator.of(context).pop();
  }
}

class _ProviderSegmentedControl extends StatelessWidget {
  const _ProviderSegmentedControl({
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
