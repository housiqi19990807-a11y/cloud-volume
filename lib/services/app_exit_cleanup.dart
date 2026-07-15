// App exit cleanup keeps desktop mount teardown on the confirmed-exit path.

import 'remote_storage_gateway.dart';

class AppExitCleanup {
  AppExitCleanup._();

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

  static Future<void> _cleanup(RemoteStorageGateway api) async {
    try {
      await api.cleanupMounts();
    } catch (_) {
      // Exit must continue even if a stale native mount cannot be deregistered.
    }
  }
}
