// Bridge error text formatting keeps common backend failures readable in UI.

String describeBridgeError(Object error) {
  final raw = _extractBridgeErrorMessage(error);
  if (raw.isEmpty) {
    return '操作失败，请稍后重试。';
  }
  final lower = raw.toLowerCase();

  if (lower.contains('create writeback queue:') &&
      lower.contains('open writeback store') &&
      lower.contains('timeout')) {
    return '当前数据库连接被残留后台进程占用，导致这次挂载无法继续。请点击“结束残留占用进程”后重试。';
  }
  if (raw.contains('SignatureDoesNotMatch')) {
    return '访问密钥或签名配置不正确。请检查 Access Key ID、Secret Access Key，以及 Endpoint、Region、Path Style 设置是否与当前 S3 服务匹配。';
  }
  if (raw.contains('InvalidAccessKeyId')) {
    return 'Access Key ID 不正确，或当前账户无权访问这个存储服务。请检查配置后重试。';
  }
  if (raw.contains('RequestTimeTooSkewed')) {
    return '本机时间与服务端时间偏差过大，签名校验失败。请同步系统时间后重试。';
  }
  if (raw.contains('NoSuchBucket')) {
    return '目标 bucket 不存在，或当前账户没有访问它的权限。';
  }
  if (_isObjectMissingRaw(raw, lower)) {
    return '文件已被删除或不存在，请刷新目录后重试。';
  }
  if (raw.contains('只读') || raw.contains('暂无写入权限')) {
    return '该目录无操作权限。';
  }
  if (raw.contains('AccessDenied') || raw.contains('StatusCode: 403')) {
    return '访问被拒绝。请检查 Access Key / Secret Key 是否正确，以及当前账户是否具备相应权限。';
  }
  if (lower.contains('connection refused') ||
      lower.contains('no such host') ||
      lower.contains('i/o timeout') ||
      lower.contains('tls handshake timeout')) {
    return '无法连接到对象存储服务。请检查 Endpoint、网络连接和代理设置后重试。';
  }
  return raw;
}

// 判定桥接错误是否表示远端对象已不存在（404/NoSuchKey 等）。
// describeBridgeError 与对外暴露的 isObjectMissingError 共用同一组关键字，
// 避免判定逻辑分散后出现两边不一致。
bool _isObjectMissingRaw(String raw, String lower) {
  return raw.contains('NoSuchKey') ||
      lower.contains('notfound') ||
      lower.contains('not found') ||
      lower.contains('file does not exist') ||
      lower.contains('statuscode: 404');
}

// 对外暴露的"对象已不存在"判定，UI 可据此隐藏下载/另存为等动作并触发元数据刷新。
bool isObjectMissingError(Object error) {
  final raw = _extractBridgeErrorMessage(error);
  if (raw.isEmpty) {
    return false;
  }
  return _isObjectMissingRaw(raw, raw.toLowerCase());
}

String _extractBridgeErrorMessage(Object error) {
  const prefix = 'RemoteStorageBridgeException: ';
  final text = error.toString().trim();
  if (text.startsWith(prefix)) {
    return text.substring(prefix.length).trim();
  }
  return text;
}
