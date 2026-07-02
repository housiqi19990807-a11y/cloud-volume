// Shared helper for generating a unique account profile key from the user label
// and storage type. Used by both the in-page dialog path and the detached
// sub-window path so naming stays consistent.

import 'package:remote_storage/models/remote_storage_config.dart';

String generateAccountProfileName(String label, StorageType storageType) {
  final normalized = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final base = normalized.isEmpty ? storageType.storageValue : normalized;
  return '${storageType.storageValue}-$base-${DateTime.now().millisecondsSinceEpoch}';
}
