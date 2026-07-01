// Shared proxy config type and HTTP client factory used by both IO and web
// implementations. Web builds use this directly; desktop builds override
// createProxyHttpClient via proxy_http_client_io.dart.

import 'package:http/http.dart' as http;

/// Proxy mode constants matching the Go config.
const String kProxyModeSystem = 'system';
const String kProxyModeDirect = 'direct';
const String kProxyModeCustom = 'custom';

class ProxyConfig {
  const ProxyConfig({
    this.mode = kProxyModeSystem,
    this.customUrl = '',
  });

  final String mode;
  final String customUrl;

  bool get isCustom => mode == kProxyModeCustom && customUrl.isNotEmpty;
  bool get isDirect => mode == kProxyModeDirect;
}

/// Creates an HTTP client.
/// Web: returns a plain client (browser handles proxy natively).
/// Desktop: overridden in proxy_http_client_io.dart to inject proxy transport.
http.Client createProxyHttpClient(ProxyConfig config) {
  return http.Client();
}
