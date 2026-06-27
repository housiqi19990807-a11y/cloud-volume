// AppLog sends Flutter diagnostics to the Go bridge log file on desktop builds.

import 'package:flutter/foundation.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

/// Unified app logging: debug console in debug mode, bridge log file on desktop.
class AppLog {
  AppLog._();

  static RemoteStorageGateway? _gateway;

  /// Call once after [RemoteStorageGateway] is ready (see AppBootstrapPage).
  static void bind(RemoteStorageGateway gateway) {
    _gateway = gateway;
  }

  static Future<void> info(String message, {String tag = 'flutter'}) =>
      _write(message, level: 'info', tag: tag);

  static Future<void> warning(String message, {String tag = 'flutter'}) =>
      _write(message, level: 'warn', tag: tag);

  static Future<void> error(String message, {String tag = 'flutter'}) =>
      _write(message, level: 'error', tag: tag);

  static Future<void> _write(
    String message, {
    required String level,
    required String tag,
  }) async {
    final text = message.trim();
    if (text.isEmpty) return;
    if (kDebugMode) {
      debugPrint('[app/$tag][$level] $text');
    }
    final gateway = _gateway;
    if (gateway == null) return;
    try {
      await gateway.writeAppLog(text, level: level, tag: tag);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[app/$tag] bridge log failed: $e');
      }
    }
  }
}
