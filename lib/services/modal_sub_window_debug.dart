// Modal presentation policy: in-app dialogs by default; OS sub-windows only
// when debug mode is on and USE_MODAL_SUB_WINDOWS is explicitly enabled.
//
// Release / normal debug runs never spawn desktop_multi_window modal editors.
// Enable with: --dart-define=USE_MODAL_SUB_WINDOWS=true (and only while
// kDebugMode is true). Web always stays on in-app modals.

import 'package:flutter/foundation.dart';

/// Compile-time opt-in for experimental OS modal sub-windows.
///
/// Defaults to false so ordinary builds never open multi-window editors.
const bool kUseModalSubWindows = bool.fromEnvironment(
  'USE_MODAL_SUB_WINDOWS',
  defaultValue: false,
);

/// Whether account / sync / remote-directory flows may open OS sub-windows.
///
/// Requires both [kDebugMode] and [kUseModalSubWindows]. File preview windows
/// are independent and are not gated by this flag.
bool get preferModalSubWindows => kDebugMode && kUseModalSubWindows;

