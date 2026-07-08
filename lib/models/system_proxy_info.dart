// Mirrors the Go `systemProxyResult` so Dart can consume the bridge response
// without duplicating field parsing at call sites.

class SystemProxyInfo {
  const SystemProxyInfo({
    required this.available,
    required this.type,
    required this.host,
    required this.port,
  });

  final bool available;
  final String type;
  final String host;
  final String port;

  factory SystemProxyInfo.fromJson(Map<String, dynamic> json) {
    return SystemProxyInfo(
      available: json['available'] as bool? ?? false,
      type: json['type'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as String? ?? '',
    );
  }
}
