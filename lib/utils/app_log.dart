// AppLog sends filtered Flutter diagnostics to the Go bridge log file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppLogLevelPreferenceKey = 'app.log.level';

enum AppLogLevel {
  silent('silent', 'Silent', 0),
  error('error', 'Error', 1),
  info('info', 'Info', 2),
  debug('debug', 'Debug', 3);

  const AppLogLevel(this.storageValue, this.label, this.priority);

  final String storageValue;
  final String label;
  final int priority;

  static AppLogLevel fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'silent' => AppLogLevel.silent,
      'error' || 'err' => AppLogLevel.error,
      'debug' => AppLogLevel.debug,
      _ => AppLogLevel.info,
    };
  }
}

/// Unified app logging: debug console in debug mode, bridge log file on desktop.
class AppLog {
  AppLog._();

  static RemoteStorageGateway? _gateway;
  static AppLogLevel _level = AppLogLevel.info;

  static AppLogLevel get level => _level;

  /// Call once after [RemoteStorageGateway] is ready (see AppBootstrapPage).
  static void bind(RemoteStorageGateway gateway) {
    _gateway = gateway;
    unawaited(loadLevel());
  }

  static Future<AppLogLevel> loadLevel() async {
    final prefs = await SharedPreferences.getInstance();
    _level = AppLogLevel.fromStorage(
      prefs.getString(kAppLogLevelPreferenceKey),
    );
    return _level;
  }

  static Future<void> setLevel(AppLogLevel level) async {
    _level = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAppLogLevelPreferenceKey, level.storageValue);
  }

  static Future<void> info(String message, {String tag = 'flutter'}) =>
      _write(message, level: AppLogLevel.info, tag: tag);

  static Future<void> warning(String message, {String tag = 'flutter'}) =>
      _write(message, level: AppLogLevel.info, tag: tag);

  static Future<void> error(String message, {String tag = 'flutter'}) =>
      _write(message, level: AppLogLevel.error, tag: tag);

  static Future<void> debug(String message, {String tag = 'flutter'}) =>
      _write(message, level: AppLogLevel.debug, tag: tag);

  static Future<void> _write(
    String message, {
    required AppLogLevel level,
    required String tag,
  }) async {
    final text = message.trim();
    if (text.isEmpty) return;
    if (_level == AppLogLevel.silent || level.priority > _level.priority) {
      return;
    }
    if (kDebugMode) {
      debugPrint('[app/$tag][${level.storageValue}] $text');
    }
    final gateway = _gateway;
    if (gateway == null) return;
    try {
      await gateway.writeAppLog(text, level: level.storageValue, tag: tag);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[app/$tag] bridge log failed: $e');
      }
    }
  }
}
