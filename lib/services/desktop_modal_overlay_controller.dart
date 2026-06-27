// Reference-counted modal scrim on the parent engine while a detached sub-window is open.

import 'package:flutter/foundation.dart';

class DesktopModalOverlayController extends ChangeNotifier {
  DesktopModalOverlayController._();

  static final DesktopModalOverlayController instance =
      DesktopModalOverlayController._();

  int _depth = 0;
  final List<String> _childWindowStack = [];

  bool get visible => _depth > 0;

  String? get topChildWindowId =>
      _childWindowStack.isEmpty ? null : _childWindowStack.last;

  void acquire() {
    _depth++;
    notifyListeners();
  }

  void release() {
    if (_depth <= 0) return;
    _depth--;
    notifyListeners();
  }

  void registerChildWindow(String windowId) {
    final id = windowId.trim();
    if (id.isEmpty) return;
    _childWindowStack.remove(id);
    _childWindowStack.add(id);
  }

  void unregisterChildWindow(String windowId) {
    _childWindowStack.remove(windowId.trim());
  }
}
