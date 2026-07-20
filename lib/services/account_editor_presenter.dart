// Account editor presentation is centralized so every caller follows the app-modal policy.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/account_editor_window_service.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';

Future<void> showAccountEditor({
  required BuildContext context,
  required RemoteStorageGateway api,
  required Future<bool> Function(RemoteStorageConfig config) onSave,
  required VoidCallback onSaved,
  Future<String> Function()? onStartBaiduPanAuthorization,
  Future<RemoteStorageConfig> Function(String displayName, String code)?
  onAuthorizeBaiduPan,
  RemoteStorageConfig? initialConfig,
  String? profileName,
  bool editing = false,
}) async {
  final openedWindow = await AccountEditorWindowService.instance.openEditor(
    initialConfigJson: initialConfig?.toJson(),
    profileName: profileName,
    editing: editing,
    onSaved: onSaved,
  );
  if (openedWindow || !context.mounted) return;

  await showAppModal<void>(
    context: context,
    builder: (_) => CloudStorageAccountDialog(
      initialConfig: initialConfig,
      editing: editing,
      onSave: onSave,
      onStartBaiduPanAuthorization:
          onStartBaiduPanAuthorization ?? api.startBaiduPanAuthorization,
      onAuthorizeBaiduPan: onAuthorizeBaiduPan ?? api.authorizeBaiduPan,
      onListBuckets: api.listBuckets,
      api: api,
    ),
  );
}
