// Conditional import: desktop builds get a proxy-aware HTTP client factory;
// web builds get a plain client (browser handles proxy natively).

export 'proxy_http_client_stub.dart'
    if (dart.library.io) 'proxy_http_client_io.dart'
    if (dart.library.html) 'proxy_http_client_web.dart';
