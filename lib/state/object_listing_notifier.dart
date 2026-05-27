// Object listing notifier keeps trash restore side effects in sync with cached file lists.

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/trash_item.dart';

class RestoredObjectEntry {
  const RestoredObjectEntry({required this.objectKey, required this.isDir});

  final String objectKey;
  final bool isDir;
}

class ObjectListingMutationEvent {
  const ObjectListingMutationEvent.restored({
    required this.version,
    required this.bucket,
    required this.entries,
  }) : kind = ObjectListingMutationKind.restored;

  final int version;
  final ObjectListingMutationKind kind;
  final String bucket;
  final List<RestoredObjectEntry> entries;
}

enum ObjectListingMutationKind { restored }

class ObjectListingNotifier extends ChangeNotifier {
  ObjectListingNotifier._();

  static final ObjectListingNotifier instance = ObjectListingNotifier._();

  ObjectListingMutationEvent? _latestEvent;
  int _version = 0;

  ObjectListingMutationEvent? get latestEvent => _latestEvent;

  void markRestored(String bucket, Iterable<TrashItem> items) {
    final entries = items
        .map(
          (item) => RestoredObjectEntry(
            objectKey: item.originalKey,
            isDir: item.isDir,
          ),
        )
        .toList(growable: false);
    if (entries.isEmpty) {
      return;
    }
    _version += 1;
    _latestEvent = ObjectListingMutationEvent.restored(
      version: _version,
      bucket: bucket,
      entries: entries,
    );
    notifyListeners();
  }
}
