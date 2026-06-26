// SyncProfileNotifier exposes the live sync profile list to the UI and polls
// runtime state so the settings page and task page see fresh statuses.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/remote_storage_api.dart';

class SyncProfileNotifier extends ChangeNotifier {
  SyncProfileNotifier._();

  static final SyncProfileNotifier instance = SyncProfileNotifier._();

  RemoteStorageGateway? _api;
  List<SyncProfileRuntime> _profiles = <SyncProfileRuntime>[];
  Timer? _poll;
  bool _loading = false;
  String? _error;

  List<SyncProfileRuntime> get profiles => _profiles;
  bool get loading => _loading;
  String? get error => _error;

  /// Polling interval for runtime state refresh. Short enough to reflect sync
  /// progress without hammering the bridge.
  static const _pollInterval = Duration(seconds: 3);

  void bindApi(RemoteStorageGateway api) {
    _api = api;
    _startPolling();
    refresh();
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      _profiles = await api.listSyncProfiles();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> saveProfile(SyncProfile profile) async {
    final api = _api;
    if (api == null) {
      throw StateError('sync api not bound');
    }
    final id = await api.saveSyncProfile(profile);
    await refresh();
    return id;
  }

  Future<void> deleteProfile(String id) async {
    final api = _api;
    if (api == null) {
      return;
    }
    await api.deleteSyncProfile(id);
    await refresh();
  }

  Future<int> triggerProfile(String id) async {
    final api = _api;
    if (api == null) {
      return 0;
    }
    final ops = await api.triggerSyncProfile(id);
    await refresh();
    return ops;
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => refresh());
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
    _api = null;
  }
}
