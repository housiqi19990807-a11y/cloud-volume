// P2P 局域网同步设置区：显示开关、分块大小配置、已发现的局域网设备列表。
// 开关切换后自动保存到配置并通知 Go 侧启用/禁用 P2P。
// 设备列表通过定时轮询 bridge get_p2p_status 获取。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// P2P settings card shown in the settings page under the 网络 group.
class SettingsP2PSection extends StatefulWidget {
  const SettingsP2PSection({
    super.key,
    required this.theme,
    required this.config,
    required this.api,
    required this.onSaveConfig,
  });

  final ShadThemeData theme;
  final RemoteStorageConfig config;
  final RemoteStorageGateway api;
  final Future<void> Function(RemoteStorageConfig) onSaveConfig;

  @override
  State<SettingsP2PSection> createState() => _SettingsP2PSectionState();
}

class _SettingsP2PSectionState extends State<SettingsP2PSection> {
  Timer? _pollTimer;
  List<_PeerInfo> _peers = [];
  String? _deviceId;
  bool _loadingPeers = false;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    if (widget.config.p2pEnabled) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant SettingsP2PSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.p2pEnabled != widget.config.p2pEnabled) {
      if (widget.config.p2pEnabled) {
        _startPolling();
      } else {
        _stopPolling();
        setState(() => _peers = []);
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _stopPolling();
    _fetchStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStatus());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchStatus() async {
    if (_loadingPeers) return;
    setState(() => _loadingPeers = true);
    try {
      final data = await widget.api.getP2PStatus();
      if (!mounted) return;
      final peersList = data['peers'] as List? ?? [];
      setState(() {
        _deviceId = data['deviceId'] as String?;
        _peers = peersList
            .map((p) => _PeerInfo(
                  deviceId: p['deviceId'] as String? ?? '',
                  addr: p['addr'] as String? ?? '',
                  lastSeen: p['lastSeen'] as String? ?? '',
                ))
            .toList();
        _loadingPeers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPeers = false);
    }
  }

  Future<void> _toggleP2P(bool enabled) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await widget.api.setP2PEnabled(enabled);
      await widget.onSaveConfig(
        widget.config.copyWith(p2pEnabled: enabled),
      );
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _saveChunkSize(int mb) async {
    await widget.onSaveConfig(
      widget.config.copyWith(p2pChunkSizeMb: mb),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEnableRow(theme),
        if (widget.config.p2pEnabled) ...[
          const SizedBox(height: 16),
          _buildChunkSizeRow(theme),
          const SizedBox(height: 16),
          _buildPeersList(theme),
        ],
      ],
    );
  }

  Widget _buildEnableRow(ShadThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('局域网 P2P 同步', style: theme.textTheme.h4),
              const SizedBox(height: 4),
              Text(
                '自动发现同账号的局域网设备，加速文件刷新和读取',
                style: theme.textTheme.muted,
              ),
            ],
          ),
        ),
        ShadSwitch(
          value: widget.config.p2pEnabled,
          onChanged: _toggling ? null : _toggleP2P,
        ),
      ],
    );
  }

  Widget _buildChunkSizeRow(ShadThemeData theme) {
    final chunkSize = widget.config.effectiveP2PChunkSizeMb;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('传输分块大小', style: theme.textTheme.h4),
              const SizedBox(height: 4),
              Text(
                '较大的分块可提高吞吐量，较小则降低内存占用',
                style: theme.textTheme.muted,
              ),
            ],
          ),
        ),
        ShadSelect<int>(
          initialValue: chunkSize,
          minWidth: 120,
          options: const [1, 2, 4, 8, 16, 32, 64].map((v) {
            return ShadOption(value: v, child: Text('$v MB'));
          }).toList(),
          selectedOptionBuilder: (context, value) => Text('$value MB'),
          onChanged: (value) {
            if (value != null) _saveChunkSize(value);
          },
        ),
      ],
    );
  }

  Widget _buildPeersList(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.monitorSmartphone,
                size: 16, color: theme.textTheme.muted.color),
            const SizedBox(width: 6),
            Text('已发现设备', style: theme.textTheme.h4),
            const Spacer(),
            if (_deviceId != null)
              Text(
                '本机: $_deviceId',
                style: theme.textTheme.muted.copyWith(fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_peers.isEmpty && !_loadingPeers)
          Text(
            '正在搜索局域网中的设备…',
            style: theme.textTheme.muted,
          )
        else if (_peers.isEmpty && _loadingPeers)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          ..._peers.map((p) => _PeerRow(peer: p, theme: theme)),
      ],
    );
  }
}

class _PeerInfo {
  final String deviceId;
  final String addr;
  final String lastSeen;

  _PeerInfo(
      {required this.deviceId, required this.addr, required this.lastSeen});
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer, required this.theme});

  final _PeerInfo peer;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(LucideIcons.laptop, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.deviceId, style: theme.textTheme.small),
                Text(peer.addr,
                    style: theme.textTheme.muted.copyWith(fontSize: 11)),
              ],
            ),
          ),
          Icon(LucideIcons.circleCheck,
              size: 14, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}
