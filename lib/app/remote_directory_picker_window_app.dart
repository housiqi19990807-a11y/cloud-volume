// Detached sub-window for browsing buckets and picking a remote directory prefix.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_directory_picker_result_payload.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/desktop_modal_window_focus_gate.dart';
import 'package:remote_storage/widgets/desktop_modal_scrim.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

class RemoteDirectoryPickerWindowApp extends StatelessWidget {
  const RemoteDirectoryPickerWindowApp({super.key, required this.args});

  final RemoteDirectoryPickerWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: '云卷 - 选择远端目录',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(AccentPreset.blue),
      home: DesktopModalWindowFocusGate(
        ancestorWindowIds: [
          if (args.rootWindowId != null) args.rootWindowId!,
          args.creatorWindowId,
        ],
        child: Stack(children: [_RemoteDirectoryPickerBody(args: args), const DesktopModalScrim()]),
      ),
    );
  }
}

class _RemoteDirectoryPickerBody extends StatefulWidget {
  const _RemoteDirectoryPickerBody({required this.args});

  final RemoteDirectoryPickerWindowArgs args;

  @override
  State<_RemoteDirectoryPickerBody> createState() =>
      _RemoteDirectoryPickerBodyState();
}

class _RemoteDirectoryPickerBodyState extends State<_RemoteDirectoryPickerBody> {
  RemoteStorageGateway? _api;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final api = await defaultRemoteStorageApiFactory();
      if (mounted) {
        setState(() {
          _api = api;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  RemoteDirectoryResult? get _initial {
    final a = widget.args;
    if (a.initialBucket == null) return null;
    final entry = a.buckets.where((b) {
      return b.bucket.name == a.initialBucket &&
          b.profileName == (a.initialProfileName ?? b.profileName);
    }).firstOrNull;
    if (entry == null) return null;
    return RemoteDirectoryResult(
      bucket: a.initialBucket!,
      prefix: a.initialPrefix ?? '',
      profileName: entry.profileName,
      config: entry.config,
    );
  }

  Future<void> _finish(RemoteDirectoryResult? result) async {
    await _sendResult(result);
        final id = (await WindowController.fromCurrentEngine()).windowId;
    DesktopModalOverlayController.instance.unregisterChildWindow(id);
    await clearModalChildWindowChrome();
    await windowManager.close();
  }

  Future<void> _sendResult(RemoteDirectoryResult? result) async {
    final payload = <String, dynamic>{
      'requestId': widget.args.requestId,
      'result': result == null
          ? null
          : RemoteDirectoryResultPayload.fromResult(result).toJson(),
    };
    final targetId = widget.args.creatorWindowId;
    final controllers = await WindowController.getAll();
    for (final c in controllers) {
      if (c.windowId == targetId) {
        await c.invokeMethod('remote_directory_picker_result', payload);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Column(
        children: [
          _PickerTitleBar(onClose: () => _finish(null)),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ShadThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _api == null) {
      return Center(child: Text(_error ?? '初始化失败', style: const TextStyle(fontSize: 13)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: RemoteDirectoryPickerDialog(
        api: _api!,
        buckets: widget.args.buckets,
        initial: _initial,
        asDialog: false,
        onCancel: () => _finish(null),
        onConfirm: (r) => _finish(r),
      ),
    );
  }
}

class _PickerTitleBar extends StatelessWidget {
  const _PickerTitleBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '选择远端目录',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
