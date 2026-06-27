// Conditional sync-editor-window service keeps browser builds away from desktop APIs.

export 'sync_editor_window_service_io.dart'
    if (dart.library.html) 'sync_editor_window_service_web.dart';
