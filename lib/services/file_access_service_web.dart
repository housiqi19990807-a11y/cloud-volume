// Browser file access uses server download URLs instead of local cache paths.

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:url_launcher/url_launcher.dart';

class FileAccessService {
  FileAccessService._();

  static final FileAccessService instance = FileAccessService._();

  Future<FilePreviewSource> preparePreviewSource({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final target = api.objectDownloadUri(bucket, object.key, inline: true);
    if (target == null) {
      throw UnsupportedError('当前客户端不支持浏览器内预览');
    }
    return FilePreviewSource(uri: target);
  }

  Future<String> preparePreviewFilePath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    throw UnsupportedError('浏览器端不支持本地预览窗口');
  }

  Future<void> openObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final target = api.objectDownloadUri(bucket, object.key, inline: true);
    if (target == null) {
      throw UnsupportedError('当前客户端不支持浏览器内预览');
    }
    await _launch(target);
  }

  Future<void> downloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    await downloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.displayName,
    );
  }

  Future<void> downloadObjectToDefaultDirectory({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    await downloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.displayName,
    );
  }

  Future<String> prepareLocalCopyPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    throw UnsupportedError('浏览器端不支持复制远端文件到系统剪贴板');
  }

  Future<void> downloadObjectToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    required String savePath,
  }) async {
    if (object.isDir) {
      throw UnsupportedError('浏览器端暂不支持文件夹下载');
    }
    final target = api.objectDownloadUri(bucket, object.key);
    if (target == null) {
      throw UnsupportedError('当前客户端不支持浏览器下载');
    }
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: savePath,
    );
    try {
      await _launch(target);
      TransferQueue.instance.markTaskDone(task.id);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      rethrow;
    }
  }

  Future<void> evictCacheForObject({
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {}

  Future<void> _launch(Uri uri) async {
    final launched = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!launched) {
      throw StateError('无法打开浏览器下载地址');
    }
  }
}
