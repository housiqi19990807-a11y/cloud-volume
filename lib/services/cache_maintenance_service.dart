// Cache maintenance service schedules rule-based cache cleanup on the desktop.
// It runs an immediate pass after bootstrap and a repeating hourly patrol so the
// cache stays within configured size/age limits without blocking the UI.

import 'dart:async';

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';

/// [CacheMaintenanceService] owns the desktop-side cache cleanup schedule.
class CacheMaintenanceService {
  CacheMaintenanceService._();

  static final CacheMaintenanceService instance = CacheMaintenanceService._();

  Timer? _patrol;
  RemoteStorageGateway? _api;
  RemoteStorageConfig? _config;
  bool _running = false;

  /// Period between automatic cleanup passes. Tuned to be unobtrusive while
  /// still catching long-running sessions that accumulate preview/mount cache.
  static const _patrolInterval = Duration(hours: 1);

  /// Configures the service with the active gateway and config snapshot.
  /// Passing a config without auto-cleanup enabled stops any prior patrol.
  void configure(RemoteStorageGateway api, RemoteStorageConfig config) {
    _api = api;
    _config = config;
    _reschedule();
  }

  /// Triggers a rule-based cleanup pass immediately when auto-cleanup is on.
  /// Safe to call before [configure]; it will no-op.
  Future<void> runOnce() async {
    final api = _api;
    final config = _config;
    if (api == null || config == null) {
      return;
    }
    if (!config.cacheAutoCleanupEnabled) {
      return;
    }
    await _runRulesPass(api, config);
  }

  /// Stops the background patrol. Called during teardown or reset.
  void stop() {
    _patrol?.cancel();
    _patrol = null;
    _api = null;
    _config = null;
  }

  void _reschedule() {
    _patrol?.cancel();
    _patrol = null;
    final config = _config;
    if (config == null || !config.cacheAutoCleanupEnabled) {
      return;
    }
    // Fire one pass immediately, then repeat on the configured interval.
    Future.microtask(runOnce);
    _patrol = Timer.periodic(_patrolInterval, (_) => runOnce());
  }

  Future<void> _runRulesPass(
    RemoteStorageGateway api,
    RemoteStorageConfig config,
  ) async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      await api.cleanCache(config, clearAll: false);
    } catch (_) {
      // Background cleanup is best-effort; failures surface in the settings card
      // when the user opens it rather than interrupting the patrol loop.
    } finally {
      _running = false;
    }
  }
}
