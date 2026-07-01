// Desktop proxy-aware HTTP client: wraps dart:io HttpClient with the configured
// proxy mode (system / direct / custom). Custom mode supports HTTP CONNECT and
// SOCKS5 proxies with optional authentication.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'proxy_http_client_stub.dart' show ProxyConfig, kProxyTypeSocks5;

// Re-export shared types so callers import one file.
export 'proxy_http_client_stub.dart'
    show
        ProxyConfig,
        kProxyModeSystem,
        kProxyModeDirect,
        kProxyModeCustom,
        kProxyTypeHttp,
        kProxyTypeSocks5;

/// Creates an [http.Client] that respects the given [ProxyConfig].
http.Client createProxyHttpClient(ProxyConfig config) {
  final client = HttpClient();

  if (config.isDirect) {
    client.findProxy = (uri) => 'DIRECT';
  } else if (config.isCustom) {
    _applyCustomProxy(client, config);
  }
  // else: system mode — leave the default (findProxyFromEnvironment) in place.

  return IOClient(client);
}

void _applyCustomProxy(HttpClient client, ProxyConfig config) {
  final host = config.host;
  final port = config.port;

  if (config.type == kProxyTypeSocks5) {
    // dart:io HttpClient findProxy supports "PROXY socks5://host:port".
    // For auth, include credentials in the proxy URL.
    final proxyUrl = config.hasAuth
        ? 'socks5://${config.username}:${config.password}@$host:$port'
        : 'socks5://$host:$port';
    client.findProxy = (uri) => 'PROXY $proxyUrl';
  } else {
    // HTTP CONNECT proxy.
    client.findProxy = (uri) => 'PROXY $host:$port';
    if (config.hasAuth) {
      // authenticateProxy is called when the proxy requests authentication;
      // returning true with credentials set via addProxyCredentials.
      client.authenticateProxy = (proxyHost, proxyPort, scheme, realm) {
        return Future.value(true);
      };
      client.addProxyCredentials(host, int.tryParse(port) ?? 0, 'basic',
        HttpClientBasicCredentials(config.username, config.password));
    }
  }
}
