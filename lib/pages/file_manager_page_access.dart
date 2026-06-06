// ignore_for_file: invalid_use_of_protected_member

// 文件管理页目录权限：按当前 WebDAV 目录刷新可写状态并控制写入口。

part of 'file_manager_page.dart';

extension _FileManagerPageAccess on _FileManagerPageState {
  bool get _currentDirectoryWritable {
    if (_activeBucket == null || _showTrash) return false;
    if (widget.config.storageType != StorageType.webdav) return true;
    if (_checkingDirectoryAccess) return false;
    final access = _directoryAccess;
    if (access == null) return false;
    return !access.known || access.writable;
  }

  Future<void> _refreshDirectoryAccess(String bucket, String prefix) async {
    try {
      final access = await widget.api.directoryAccess(
        widget.config,
        bucket,
        prefix,
      );
      if (!mounted || _activeBucket != bucket || _prefix != prefix) return;
      setState(() {
        _directoryAccess = access;
        _checkingDirectoryAccess = false;
      });
    } catch (error) {
      if (!mounted || _activeBucket != bucket || _prefix != prefix) return;
      setState(() {
        _directoryAccess = const DirectoryAccess(writable: true, known: false);
        _checkingDirectoryAccess = false;
      });
    }
  }

  bool _ensureCurrentDirectoryWritable() {
    if (_currentDirectoryWritable) return true;
    final reason = _directoryAccess?.reason.trim();
    _showPageMessage(
      title: '当前目录不可写',
      message: reason?.isNotEmpty == true ? reason! : '当前 WebDAV 目录暂无写入权限。',
    );
    return false;
  }
}
