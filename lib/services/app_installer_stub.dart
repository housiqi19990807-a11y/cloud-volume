// Web stub: in-app self-install is not available in the browser.

import 'package:remote_storage/services/app_update_service.dart';

/// Always `false` on the web platform — there is no local install path.
const bool kSupportsInAppInstall = false;

/// Downloads and installs the given asset, reporting progress.
///
/// Returns a human-readable error on the web platform, since browsers
/// cannot write to the local filesystem or launch installers.
Future<String> downloadAndInstallAsset(
  ReleaseAsset asset,
  String installerType, {
  void Function(int received, int total)? onProgress,
}) async {
  return 'Web 端不支持应用内自动更新，请前往 GitHub 下载。';
}
