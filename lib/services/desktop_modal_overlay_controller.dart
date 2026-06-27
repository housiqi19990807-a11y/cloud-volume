// Reference-counted modal scrim on the parent engine while a detached sub-window is open.

import 'package:flutter/foundation.dart';

class DesktopModalOverlayController extends ChangeNotifier {
  DesktopModalOverlayController._();

  static final DesktopModalOverlayController instance =
      DesktopModalOverlayController._();

  int _depth = 0;

  bool get visible => _depth > 0;

  void acquire() {
    _depth++;
    notifyListeners();
  }

  void release() {
    if (_depth <= 0) return;
    _depth--;
    notifyListeners();
  }
}
