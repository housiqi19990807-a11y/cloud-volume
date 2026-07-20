part of 'remote_storage_api_web.dart';

// Web bucket metadata and browser transfer calls share the HTTP API transport.
mixin _RemoteStorageWebTransferApiMixin
    implements RemoteStorageGateway, BucketQuotaQuery {
  http.Client get _client;

  Uri _apiUri(String path, [Map<String, String>? queryParameters]);

  dynamic _decodeResponse(http.Response response);

  Future<dynamic> _invoke(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);

  List<T> _parseList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  );

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async {
    final result = await _invoke('list_buckets');
    return _parseList(result, (m) => BucketInfo.fromJson(m));
  }

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    final result = await _invoke('get_bucket_quota', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketInfo.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) {
    throw UnsupportedError('Web 端上传使用浏览器内存文件，不走本地路径');
  }

  @override
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  ) {
    throw UnsupportedError('Web 端暂不支持本地目录上传');
  }

  @override
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _apiUri('/api/upload', {'bucket': bucket, 'key': key, 'taskId': taskId}),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName.isEmpty ? key.split('/').last : fileName,
      ),
    );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _decodeResponse(response);
  }

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) {
    throw UnsupportedError('Web 端下载使用浏览器地址，不写入本地路径');
  }

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) {
    return _apiUri('/api/download', <String, String>{
      'bucket': bucket,
      'key': key,
      if (inline) 'inline': '1',
    });
  }

  @override
  Uri? webDavUri(String bucket) {
    return _apiUri('/webdav/$bucket/');
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    await _invoke('cancel_transfer', <String, dynamic>{'taskId': taskId});
  }

  @override
  Future<bool> triggerTransfer(String taskId) async {
    final result = await _invoke('trigger_transfer', <String, dynamic>{
      'taskId': taskId,
    });
    if (result is Map<String, dynamic>) {
      return result['ok'] == true;
    }
    return result == true;
  }

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async {
    final result = await _invoke('list_transfer_jobs');
    return _parseList(result, (m) => TransferSnapshot.fromJson(m));
  }
}
