// Share records notifier lets file actions and the share page stay in sync.

import 'package:flutter/foundation.dart';

class ShareRecordsNotifier extends ChangeNotifier {
  ShareRecordsNotifier._();

  static final ShareRecordsNotifier instance = ShareRecordsNotifier._();

  void markChanged() {
    notifyListeners();
  }
}
