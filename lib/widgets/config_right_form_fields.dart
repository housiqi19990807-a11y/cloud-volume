// 首次启动连接表单的字段布局：单列 / 两列与输入控件构建。
// 作为 config_right_form.dart 的 part，接收宿主 panel 以访问字段。

part of 'config_right_form.dart';

/// 窄布局：字段自上而下排列。
Widget buildConfigFormSingleColumnFields(
  ConfigRightFormPanel self,
  BuildContext context, {
  required bool isBaiduPan,
}) {
  final isWebDav = self.storageType == StorageType.webdav;
  final isFTP = self.storageType == StorageType.ftp ||
      self.storageType == StorageType.sftp;
  final usesWebDAVCreds = isWebDav || isFTP;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      self._fieldLabel(context, '名称'),
      const SizedBox(height: 6),
      _configFormNameInput(self, isWebDav: isWebDav, isBaiduPan: isBaiduPan, isFTP: isFTP),
      if (usesWebDAVCreds) ...[
        const SizedBox(height: 18),
        self._fieldLabel(context, '映射桶名称'),
        const SizedBox(height: 6),
        _configFormMappedBucketInput(self),
        const SizedBox(height: 18),
      ],
      if (!usesWebDAVCreds && !isBaiduPan) ...[
        const SizedBox(height: 18),
      ],
      if (isBaiduPan) ...[
        const SizedBox(height: 18),
        BaiduPanAuthSection(
          accountLabel: self.baiduPanAccountLabel,
          authorized: self.baiduPanAuthorized,
          codeController: self.baiduPanCodeController,
          authUrl: self.baiduPanAuthUrl,
          openingBrowser: self.baiduPanOpeningBrowser,
          submittingCode: self.baiduPanAuthorizing,
          onOpenAuthorizationPage: self.onStartBaiduPanAuthorization,
          onSubmitAuthorizationCode: self.onAuthorizeBaiduPan,
        ),
      ] else ...[
        self._fieldLabel(
          context,
          isWebDav
              ? 'WebDAV 地址'
              : isFTP
              ? 'FTP 地址'
              : '网关地址',
        ),
        const SizedBox(height: 6),
        _configFormEndpointInput(self, isWebDav: isWebDav, isFTP: isFTP),
        const SizedBox(height: 22),
      ],
      if (!isBaiduPan &&
          usesWebDAVCreds &&
          self.webdavUsernameController != null &&
          self.webdavPasswordController != null) ...[
        self._fieldLabel(context, '用户名'),
        const SizedBox(height: 6),
        if (isFTP && self.ftpUsernameController != null)
          ShadInput(
            controller: self.ftpUsernameController!,
            placeholder: const Text('输入用户名'),
          )
        else
          _configFormWebdavUsernameInput(self),
        const SizedBox(height: 18),
        self._fieldLabel(context, '密码'),
        const SizedBox(height: 6),
        if (isFTP && self.ftpPasswordController != null)
          CloudStorageSecretInput(
            controller: self.ftpPasswordController!,
            placeholder: Text(
              self.hasStoredFtpPassword
                  ? '留空则保留当前已保存的密码'
                  : '输入登录密码',
            ),
          )
        else
          _configFormWebdavPasswordInput(self),
      ] else if (!isBaiduPan) ...[
        self._fieldLabel(context, '访问密钥 ID'),
        const SizedBox(height: 6),
        _configFormAccessKeyInput(self),
        const SizedBox(height: 18),
        self._fieldLabel(context, '访问密钥'),
        const SizedBox(height: 6),
        _configFormSecretKeyInput(self),
      ],
      if (!usesWebDAVCreds && !isBaiduPan) ...[
        const SizedBox(height: 18),
        _AdvancedSettingsLink(
          onTap: self.isSaving ? null : () => self.openAdvancedDialog(context),
        ),
      ],
    ],
  );
}

/// 全屏宽布局：连接信息与凭据分两列，减少纵向堆叠。
Widget buildConfigFormTwoColumnFields(
  ConfigRightFormPanel self,
  BuildContext context,
) {
  final isWebDav = self.storageType == StorageType.webdav;
  final isFTP = self.storageType == StorageType.ftp ||
      self.storageType == StorageType.sftp;
  final usesWebDAVCreds = isWebDav || isFTP;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            self._fieldLabel(context, '名称'),
            const SizedBox(height: 6),
            _configFormNameInput(
              self,
              isWebDav: isWebDav,
              isBaiduPan: false,
              isFTP: isFTP,
            ),
            if (usesWebDAVCreds) ...[
              const SizedBox(height: 18),
              self._fieldLabel(context, '映射桶名称'),
              const SizedBox(height: 6),
              _configFormMappedBucketInput(self),
            ],
            const SizedBox(height: 18),
            self._fieldLabel(
              context,
              isWebDav
                  ? 'WebDAV 地址'
                  : isFTP
                  ? 'FTP 地址'
                  : '网关地址',
            ),
            const SizedBox(height: 6),
            _configFormEndpointInput(self, isWebDav: isWebDav, isFTP: isFTP),
            if (!usesWebDAVCreds) ...[
              const SizedBox(height: 18),
              _AdvancedSettingsLink(
                onTap:
                    self.isSaving ? null : () => self.openAdvancedDialog(context),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 28),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (usesWebDAVCreds &&
                self.webdavUsernameController != null &&
                self.webdavPasswordController != null) ...[
              self._fieldLabel(context, '用户名'),
              const SizedBox(height: 6),
              _configFormWebdavUsernameInput(self),
              const SizedBox(height: 18),
              self._fieldLabel(context, '密码'),
              const SizedBox(height: 6),
              _configFormWebdavPasswordInput(self),
            ] else ...[
              self._fieldLabel(context, '访问密钥 ID'),
              const SizedBox(height: 6),
              _configFormAccessKeyInput(self),
              const SizedBox(height: 18),
              self._fieldLabel(context, '访问密钥'),
              const SizedBox(height: 6),
              _configFormSecretKeyInput(self),
            ],
          ],
        ),
      ),
    ],
  );
}

Widget _configFormNameInput(
  ConfigRightFormPanel self, {
  required bool isWebDav,
  required bool isBaiduPan,
  bool isFTP = false,
}) {
  return ShadInput(
    controller: self.nameController,
    placeholder: Text(
      isBaiduPan
          ? '例如：我的百度网盘'
          : isWebDav
          ? '例如：IHEP WebDAV'
          : isFTP
          ? '例如：我的 FTP 服务器'
          : '例如：对象存储账号',
    ),
    onChanged: self.onNameChanged,
  );
}

Widget _configFormMappedBucketInput(ConfigRightFormPanel self) {
  return ShadInput(
    controller: self.mappedBucketNameController,
    placeholder: const Text('默认使用名称'),
    onChanged: self.onMappedBucketNameChanged,
  );
}

Widget _configFormEndpointInput(
  ConfigRightFormPanel self, {
  required bool isWebDav,
  bool isFTP = false,
}) {
  return CloudStorageTechnicalInput(
    controller: self.endpointController,
    keyboardType: TextInputType.url,
    placeholder: Text(
      isWebDav
          ? 'https://webdav-ocloud.ihep.ac.cn'
          : isFTP
          ? 'host:21 或 ftp://host:21'
          : 'https://fgws3-ocloud.ihep.ac.cn',
    ),
  );
}

Widget _configFormWebdavUsernameInput(ConfigRightFormPanel self) {
  return CloudStorageTechnicalInput(
    controller: self.webdavUsernameController!,
    placeholder: const Text('输入 WebDAV 用户名'),
  );
}

Widget _configFormWebdavPasswordInput(ConfigRightFormPanel self) {
  return CloudStorageSecretInput(
    controller: self.webdavPasswordController!,
    placeholder: Text(
      self.hasStoredWebdavPassword
          ? '留空则保留当前已保存的 WebDAV 密码'
          : '输入 WebDAV 登录密码',
    ),
  );
}

Widget _configFormAccessKeyInput(ConfigRightFormPanel self) {
  return CloudStorageTechnicalInput(
    controller: self.accessKeyController,
    placeholder: const Text('输入 Access Key ID'),
  );
}

Widget _configFormSecretKeyInput(ConfigRightFormPanel self) {
  return CloudStorageSecretInput(
    controller: self.secretKeyController,
    placeholder: Text(
      self.hasStoredSecretKey
          ? '留空则保留当前已保存的 Secret Access Key'
          : '输入 Secret Access Key',
    ),
  );
}
