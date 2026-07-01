// Desktop proxy-aware HTTP client: wraps dart:io HttpClient with the configured
// proxy mode (system / direct / custom) so all Dart-side http requests respect
// the user's proxy settings.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'proxy_http_client_stub.dart' show ProxyConfig;

// Re-export the shared types so callers import one file.
export 'proxy_http_client_stub.dart'
    show ProxyConfig, kProxyModeSystem, kProxyModeDirect, kProxyModeCustom;

/// Creates an [http.Client] that respects the given [ProxyConfig].
///
/// - system: reads `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` env vars
///   via the default [HttpClient] behavior.
/// - direct: ignores all proxies.
/// - custom: forces the specified proxy URL.
http.Client createProxyHttpClient(ProxyConfig config) {
  final client = HttpClient();

  if (config.isDirect) {
    // Direct mode: ignore all proxy environment variables.
    client.findProxy = (uri) => 'DIRECT';
  } else if (config.isCustom) {
    final proxyUri = config.customUrl;
    client.findProxy = (uri) => 'PROXY $proxyUri';
  }
  // else: system mode -- leave the default (findProxyFromEnvironment) in place.

  return IOClient(client);
}
