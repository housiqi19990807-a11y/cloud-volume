// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页挂载逻辑：刷新状态，并暴露挂载、卸载和打开挂载目录动作。

extension _FileManagerPageMount on _FileManagerPageState {
  Future<void> _refreshMountStatus(String bucket) async {
    try {
      final status = await widget.api.getBucketMountStatus(bucket);
      if (!mounted || _activeBucket != bucket) return;
      setState(() => _mountStatus = status);
    } catch (_) {
      // 挂载状态查询失败不阻断文件浏览；用户显式操作时再显示错误。
    }
  }

  Future<void> _mountBucket() async {
    if (_activeBucket == null || _mountBusy) return;
    setState(() => _mountBusy = true);
    try {
      final status = await widget.api.mountBucket(
        widget.config,
        _activeBucket!,
      );
      if (!mounted) return;
      setState(() => _mountStatus = status);
    } catch (error) {
      _showPageError(error);
    } finally {
      if (mounted) {
        setState(() => _mountBusy = false);
      }
    }
  }

  Future<void> _unmountBucket() async {
    if (_activeBucket == null || _mountBusy) return;
    setState(() => _mountBusy = true);
    try {
      final status = await widget.api.unmountBucket(_activeBucket!);
      if (!mounted) return;
      setState(() => _mountStatus = status);
    } catch (error) {
      _showPageError(error);
    } finally {
      if (mounted) {
        setState(() => _mountBusy = false);
      }
    }
  }

  Future<void> _openMountedBucket() async {
    if (_activeBucket == null) return;
    try {
      final status = await widget.api.openBucketMount(_activeBucket!);
      if (!mounted) return;
      setState(() => _mountStatus = status);
    } catch (error) {
      _showPageError(error);
    }
  }
}
