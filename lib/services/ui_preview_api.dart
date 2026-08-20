// HTTP-shaped in-memory API used only to render the existing UI without a backend.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:remote_storage/services/remote_storage_api_web.dart';

Future<RemoteStorageApi> createUiPreviewApi() async {
  return RemoteStorageApi(client: _PreviewClient());
}

class _PreviewClient extends http.BaseClient {
  bool _authenticated = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    Object result;
    if (path == '/api/auth/session') {
      result = <String, dynamic>{
        'authenticated': _authenticated,
        'loginRequired': true,
      };
    } else if (path == '/api/auth/login') {
      _authenticated = true;
      result = const <String, dynamic>{};
    } else if (path == '/api/auth/logout') {
      _authenticated = false;
      result = const <String, dynamic>{};
    } else if (path.endsWith('/load_bootstrap_state')) {
      result = <String, dynamic>{
        'configPath': 'ui-preview',
        'configured': true,
        'config': <String, dynamic>{},
        'profiles': <dynamic>[],
      };
    } else if (path.endsWith('/list_buckets') ||
        path.endsWith('/list_objects') ||
        path.endsWith('/list_transfers')) {
      result = const <dynamic>[];
    } else {
      result = <String, dynamic>{};
    }
    final body = jsonEncode(<String, dynamic>{'ok': true, 'result': result});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }
}
