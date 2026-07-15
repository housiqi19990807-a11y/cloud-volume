// App exit cleanup keeps desktop mount teardown on the confirmed-exit path.

import 'remote_storage_gateway.dart';

class AppExitCleanup {
  AppExitCleanup._();

  static const Duration _cleanupTimeout = Duration(seconds: 30);

  static RemoteStorageGateway? _api;
  static Future<void>? _inFlight;

  static void register(RemoteStorageGateway api) {
    _api = api;
  }

  static Future<void> cleanupMounts() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final api = _api;
    if (api == null) return Future<void>.value();

    final future = _cleanup(api);
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  static Future<int> activeMountCount() async {
    final api = _api;
    if (api == null || api is! ActiveMountQuery) return 0;
    try {
      return await (api as ActiveMountQuery).getActiveMountCount();
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _cleanup(RemoteStorageGateway api) async {
    try {
      await api.cleanupMounts().timeout(_cleanupTimeout);
    } catch (_) {
      // Exit must continue even if a stale native mount cannot be deregistered.
    }
  }
}
