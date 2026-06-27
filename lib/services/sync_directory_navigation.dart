// 主窗口接收子窗口或同步页的「打开远端目录」请求并驱动文件管理导航。

import 'dart:async';

import 'package:remote_storage/models/sync_remote_open_request.dart';

typedef SyncRemoteOpenHandler = void Function(SyncRemoteOpenRequest request);

/// 单例事件总线：AppBootstrap 注册 handler，同步页/子窗口发起跳转。
class SyncDirectoryNavigation {
  SyncDirectoryNavigation._();

  static final SyncDirectoryNavigation instance = SyncDirectoryNavigation._();

  SyncRemoteOpenHandler? _handler;

  void setHandler(SyncRemoteOpenHandler? handler) {
    _handler = handler;
  }

  void openRemote(SyncRemoteOpenRequest request) {
    if (request.bucket.trim().isEmpty) return;
    _handler?.call(request);
  }
}
