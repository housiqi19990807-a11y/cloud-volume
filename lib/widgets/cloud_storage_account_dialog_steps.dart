// ignore_for_file: library_private_types_in_public_api
part of 'cloud_storage_account_dialog.dart';

// ---------------------------------------------------------------------------
// Step 1 — Protocol picker: large selectable cards for S3 / WebDAV / Baidu Pan
// ---------------------------------------------------------------------------

/// 步骤 1「选择接入协议」的卡片列表。每个协议显示图标 + 名称 + 简短说明。
Widget stepProtocolPicker({
  required ShadThemeData theme,
  required _CloudStorageAccountDialogState self,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final type in StorageType.values) ...[
        StorageProtocolCard(
          type: type,
          selected: self._storageType == type,
          onTap: () => self.markDirty(() => self._storageType = type),
        ),
        if (type != StorageType.values.last) const SizedBox(height: 10),
      ],
    ],
  );
}

/// 协议选择卡片：hover 高亮、选中时 primary 边框 + 淡色底。
class StorageProtocolCard extends StatefulWidget {
  const StorageProtocolCard({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final StorageType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<StorageProtocolCard> createState() => _StorageProtocolCardState();
}

class _StorageProtocolCardState extends State<StorageProtocolCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final borderColor = widget.selected
        ? theme.colorScheme.primary
        : (_hovered
            ? theme.colorScheme.primary.withValues(alpha: 0.5)
            : theme.colorScheme.border);
    final bg = widget.selected
        ? theme.colorScheme.primary.withValues(alpha: 0.06)
        : (_hovered
            ? theme.colorScheme.secondary
            : theme.colorScheme.background);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _iconFor(widget.type),
                size: 22,
                color: widget.selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.type.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _descriptionFor(widget.type),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.selected)
                Icon(
                  LucideIcons.check,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(StorageType type) {
    return switch (type) {
      StorageType.s3 => LucideIcons.database,
      StorageType.webdav => LucideIcons.folderOpen,
      StorageType.baiduPan => LucideIcons.cloud,
    };
  }

  static String _descriptionFor(StorageType type) {
    return switch (type) {
      StorageType.s3 => 'Amazon S3、MinIO 及兼容的对象存储服务',
      StorageType.webdav => '通过 WebDAV 协议挂载的远端文件服务',
      StorageType.baiduPan => '使用百度网盘 OAuth 授权接入个人网盘',
    };
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Connection fields: name + protocol-specific details + proxy
// ---------------------------------------------------------------------------

/// 步骤 2「配置连接信息」：名称字段 + 对应协议的连接参数 + 代理设置。
Widget stepConnectionFields({
  required ShadThemeData theme,
  required _CloudStorageAccountDialogState self,
}) {
  final isWebDav = self._storageType == StorageType.webdav;
  final isBaiduPan = self._storageType == StorageType.baiduPan;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CloudStorageLabeledField(
        label: '名称',
        child: ShadInput(
          controller: self._nameController,
          placeholder: Text(
            isBaiduPan
                ? '例如：我的百度网盘'
                : isWebDav
                    ? '例如：IHEP WebDAV'
                    : '例如：对象存储账号',
          ),
          onChanged: (_) => self._syncMappedBucketName(),
        ),
      ),
      if (isWebDav) ...[
        const SizedBox(height: 14),
        CloudStorageLabeledField(
          label: '映射桶名称',
          child: ShadInput(
            controller: self._mappedBucketNameController,
            placeholder: const Text('默认使用名称'),
            onChanged: (_) => self._mappedBucketNameEdited = true,
          ),
        ),
      ],
      const SizedBox(height: 14),
      if (isBaiduPan) ..._baiduPanFields(self),
      if (!isBaiduPan && !isWebDav) ..._s3Fields(self),
      if (!isBaiduPan && isWebDav) ..._webdavFields(self),
      const SizedBox(height: 18),
      AccountProxySection(
        initialMode: self._proxyMode,
        initialType: self._proxyType,
        hostController: self._proxyHostController,
        portController: self._proxyPortController,
        usernameController: self._proxyUsernameController,
        passwordController: self._proxyPasswordController,
        onModeChanged: (value) => self._proxyMode = value,
        onTypeChanged: (value) => self._proxyType = value,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// S3 advanced options (path-style toggle)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Protocol-specific field builders (called from stepConnectionFields)
// ---------------------------------------------------------------------------

/// S3 fields: endpoint, region, access key, secret key, path-style switch.
List<Widget> _s3Fields(_CloudStorageAccountDialogState self) {
  return [
    CloudStorageLabeledField(
      label: '网关地址',
      child: CloudStorageTechnicalInput(
        controller: self._endpointController,
        keyboardType: TextInputType.url,
        placeholder: const Text('https://s3.example.com'),
      ),
    ),
    const SizedBox(height: 14),
    CloudStorageLabeledField(
      label: '区域',
      child: CloudStorageTechnicalInput(
        controller: self._regionController,
        placeholder: const Text('Region，例如 auto'),
      ),
    ),
    const SizedBox(height: 14),
    CloudStorageLabeledField(
      label: '访问密钥 ID',
      child: CloudStorageTechnicalInput(
        controller: self._accessKeyController,
        placeholder: const Text('Access Key ID'),
      ),
    ),
    const SizedBox(height: 14),
    CloudStorageLabeledField(
      label: '访问密钥',
      child: CloudStorageSecretInput(
        controller: self._secretKeyController,
        placeholder: Text(
          self.widget.editing
              ? '留空则保留当前 Secret Key'
              : 'Secret Access Key',
        ),
      ),
    ),
    const SizedBox(height: 16),
    _S3AdvancedOptions(
      usePathStyle: self._usePathStyle,
      onPathStyleChanged: (value) =>
          self.markDirty(() => self._usePathStyle = value),
    ),
  ];
}

/// WebDAV fields: URL, username, password.
List<Widget> _webdavFields(_CloudStorageAccountDialogState self) {
  return [
    CloudStorageLabeledField(
      label: 'WebDAV 地址',
      child: CloudStorageTechnicalInput(
        controller: self._endpointController,
        keyboardType: TextInputType.url,
        placeholder: const Text(
          'https://dav.example.com/remote.php/dav/files/me',
        ),
      ),
    ),
    const SizedBox(height: 14),
    CloudStorageLabeledField(
      label: '用户名',
      child: CloudStorageTechnicalInput(
        controller: self._webdavUsernameController,
        placeholder: const Text('输入 WebDAV 用户名'),
      ),
    ),
    const SizedBox(height: 14),
    CloudStorageLabeledField(
      label: '密码',
      child: CloudStorageSecretInput(
        controller: self._webdavPasswordController,
        placeholder: Text(
          self.widget.editing
              ? '留空则保留当前 WebDAV 密码'
              : '输入 WebDAV 登录密码',
        ),
      ),
    ),
  ];
}

/// Baidu Pan fields: OAuth authorization section.
List<Widget> _baiduPanFields(_CloudStorageAccountDialogState self) {
  final label =
      self._authorizedBaiduConfig?.displayName.trim().isNotEmpty == true
          ? self._authorizedBaiduConfig!.displayName
          : self._nameController.text.trim();
  return [
    BaiduPanAuthSection(
      accountLabel: label,
      authorized:
          self._authorizedBaiduConfig?.accessKeyId.trim().isNotEmpty == true &&
              self._authorizedBaiduConfig?.hasSecretAccessKey == true,
      codeController: self._baiduAuthCodeController,
      authUrl: self._baiduAuthUrl,
      openingBrowser: self._openingBaiduAuthPage,
      submittingCode: self._authorizingBaidu,
      onOpenAuthorizationPage: self._startBaiduPanAuthorization,
      onSubmitAuthorizationCode: self._authorizeBaiduPan,
      errorText: self._baiduAuthErrorText,
    ),
  ];
}
