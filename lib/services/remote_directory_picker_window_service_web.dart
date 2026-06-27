// Web has no detached picker window; callers fall back to ShadDialog.

import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';

class RemoteDirectoryPickerWindowService {
  RemoteDirectoryPickerWindowService._();

  static final RemoteDirectoryPickerWindowService instance =
      RemoteDirectoryPickerWindowService._();

  bool get isSupported => false;

  Future<RemoteDirectoryResult?> openPicker({
    required List<FileManagerBucketEntry> buckets,
    RemoteDirectoryResult? initial,
  }) async {
    return null;
  }
}
