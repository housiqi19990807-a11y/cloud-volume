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
  // Wide dialog: put protocol cards in one row so step 1 stays short.
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < StorageType.values.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: StorageProtocolCard(
            type: StorageType.values[i],
            selected: self._storageType == StorageType.values[i],
            onTap: () => self.markDirty(
              () => self._storageType = StorageType.values[i],
            ),
            compact: true,
          ),
        ),
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
    this.compact = false,
  });

  final StorageType type;
  final bool selected;
  final VoidCallback onTap;

  /// When true, stack icon / title / description for a multi-column row.
  final bool compact;

  @override
  State<StorageProtocolCard> createState() => _StorageProtocolCardState();
}

class _StorageProtocolCardState extends State<StorageProtocolCard> {
  // Hover must live on this State (not an inline builder). See AGENTS.md
  // "Hover-aware clickable rows" binding rule.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interaction = ListInteractionColors.fromTheme(theme);
    // Fixed border width avoids layout jump under content-fit measurement.
    const borderWidth = 1.0;
    // Hover is a neutral wash only — same family as file-list rows.
    // Do NOT switch to primary border / secondary blue fill / blue icon on
    // hover; that reads as a different component style, not a hover state.
    final borderColor = widget.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.border;
    final bg = interaction.rowBackground(
      selected: widget.selected,
      hovered: _hovered,
      pressed: false,
    );
    final iconColor = widget.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: widget.compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_iconFor(widget.type), size: 20, color: iconColor),
                        const Spacer(),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: widget.selected
                              ? Icon(
                                  LucideIcons.check,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.type.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _descriptionFor(widget.type),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(_iconFor(widget.type), size: 22, color: iconColor),
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
                    // Reserve checkmark width so select does not reflow card height.
                    SizedBox(
                      width: 18,
                      child: widget.selected
                          ? Icon(
                              LucideIcons.check,
                              size: 18,
                              color: theme.colorScheme.primary,
                            )
                          : null,
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
/// 宽对话框下用双列排布，减少纵向滚动。
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
      if (isWebDav)
        _twoColumnRow(
          left: CloudStorageLabeledField(
            label: '名称',
            child: ShadInput(
              controller: self._nameController,
              placeholder: const Text('例如：IHEP WebDAV'),
              onChanged: (_) => self._syncMappedBucketName(),
            ),
          ),
          right: CloudStorageLabeledField(
            label: '映射桶名称',
            child: ShadInput(
              controller: self._mappedBucketNameController,
              placeholder: const Text('默认使用名称'),
              onChanged: (_) => self._mappedBucketNameEdited = true,
            ),
          ),
        )
      else
        CloudStorageLabeledField(
          label: '名称',
          child: ShadInput(
            controller: self._nameController,
            placeholder: Text(
              isBaiduPan ? '例如：我的百度网盘' : '例如：对象存储账号',
            ),
            onChanged: (_) => self._syncMappedBucketName(),
          ),
        ),
      const SizedBox(height: 12),
      if (isBaiduPan) ..._baiduPanFields(self),
      if (!isBaiduPan && !isWebDav) ..._s3Fields(self),
      if (!isBaiduPan && isWebDav) ..._webdavFields(self),
      const SizedBox(height: 14),
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

/// Two equal columns with a fixed gutter; keeps tall forms shorter.
Widget _twoColumnRow({required Widget left, required Widget right}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      Expanded(child: right),
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
    const SizedBox(height: 12),
    _twoColumnRow(
      left: CloudStorageLabeledField(
        label: '区域',
        child: CloudStorageTechnicalInput(
          controller: self._regionController,
          placeholder: const Text('Region，例如 auto'),
        ),
      ),
      right: CloudStorageLabeledField(
        label: '访问密钥 ID',
        child: CloudStorageTechnicalInput(
          controller: self._accessKeyController,
          placeholder: const Text('Access Key ID'),
        ),
      ),
    ),
    const SizedBox(height: 12),
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
    const SizedBox(height: 12),
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
    const SizedBox(height: 12),
    _twoColumnRow(
      left: CloudStorageLabeledField(
        label: '用户名',
        child: CloudStorageTechnicalInput(
          controller: self._webdavUsernameController,
          placeholder: const Text('输入 WebDAV 用户名'),
        ),
      ),
      right: CloudStorageLabeledField(
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
