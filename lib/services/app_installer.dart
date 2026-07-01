// Conditional import: desktop platforms get the real installer; web gets a stub.

export 'app_installer_stub.dart'
    if (dart.library.io) 'app_installer_io.dart'
    if (dart.library.html) 'app_installer_web.dart';
