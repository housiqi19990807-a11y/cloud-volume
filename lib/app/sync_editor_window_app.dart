// Sync editor sub-window built on the shared DesktopModalSubWindowApp.
// Owns only the bridge bootstrap (load profiles + bucket list), the save
// callback, and the SyncProfileNotifier binding. Title bar, scrim, lifecycle,
// loading/error states, and close sequence are handled by the generic shell.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/file_sync_profile_editor.dart';
import 'package:remote_storage/app/desktop_modal_sub_window_app.dart';

class SyncEditorWindowApp extends StatelessWidget {
  const SyncEditorWindowApp({super.key, required this.args});

  final SyncEditorWindowArgs args;

  @override
  Widget build(BuildContext context) {
    final isEdit = args.initialProfile != null;
    return DesktopModalSubWindowApp<_SyncBootstrapResult>(
      title: isEdit ? '编辑同步配置' : '新建同步配置',
      creatorWindowId: args.creatorWindowId,
      bootstrap: () async {
        DesktopWindowMethodHost.ensureInstalled();
        final api = await defaultRemoteStorageApiFactory();
        SyncProfileNotifier.instance.bindApi(api);
        final entries = <FileManagerBucketEntry>[];
        for (final name in args.profileNames) {
          final config = await api.loadProfile(name);
          final buckets = await api.listBuckets(config);
          final sourceLabel = _sourceLabel(config);
          for (final bucket in buckets) {
            entries.add(FileManagerBucketEntry.fromBucketInfo(
              bucket: bucket,
              profileName: name,
              sourceLabel: sourceLabel,
              config: config,
            ));
          }
        }
        entries.sort((a, b) {
          final sc = a.sourceLabel.compareTo(b.sourceLabel);
          return sc != 0 ? sc : a.bucket.name.compareTo(b.bucket.name);
        });
        return _SyncBootstrapResult(api: api, buckets: entries);
      },
      contentBuilder: (context, data) => _SyncEditorContent(
        args: args,
        api: data.api,
        buckets: data.buckets,
      ),
    );
  }

  String _sourceLabel(RemoteStorageConfig config) {
    final name = config.displayName.trim().isNotEmpty
        ? config.displayName.trim()
        : config.storageType == StorageType.baiduPan
            ? '百度网盘'
            : config.storageType == StorageType.webdav
                ? config.webdavUsername.trim()
                : config.accessKeyId.trim();
    return name.isEmpty ? '账号' : name;
  }
}

/// Carries the bootstrapped gateway + bucket list across the generic shell.
class _SyncBootstrapResult {
  const _SyncBootstrapResult({required this.api, required this.buckets});

  final RemoteStorageGateway api;
  final List<FileManagerBucketEntry> buckets;
}

/// Holds the save callback and SyncProfileNotifier lifecycle for
/// [FileSyncProfileEditor].
class _SyncEditorContent extends StatefulWidget {
  const _SyncEditorContent({
    required this.args,
    required this.api,
    required this.buckets,
  });

  final SyncEditorWindowArgs args;
  final RemoteStorageGateway api;
  final List<FileManagerBucketEntry> buckets;

  @override
  State<_SyncEditorContent> createState() => _SyncEditorContentState();
}

class _SyncEditorContentState extends State<_SyncEditorContent> {
  @override
  void dispose() {
    SyncProfileNotifier.instance.stop();
    super.dispose();
  }

  Future<bool> _onSave(SyncProfile profile) async {
    try {
      await SyncProfileNotifier.instance.saveProfile(profile);
      return true;
    } catch (e) {
      if (!mounted) return false;
      showAppErrorToast(context, message: '保存失败：$e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FileSyncProfileEditor(
      api: widget.api,
      buckets: widget.buckets,
      initial: widget.args.initialProfile,
      onSave: _onSave,
      onSaved: () {},
      asDialog: false,
      creatorWindowId: widget.args.creatorWindowId,
      anchorFrameLeft: widget.args.creatorFrameLeft,
      anchorFrameTop: widget.args.creatorFrameTop,
      anchorFrameWidth: widget.args.creatorFrameWidth,
      anchorFrameHeight: widget.args.creatorFrameHeight,
    );
  }
}
