// Paged listing models keep continuation-token based bridge responses typed in Flutter.

import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';

class ObjectListPage {
  const ObjectListPage({required this.items, required this.nextToken});

  factory ObjectListPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ObjectListPage(
      items: rawItems is List
          ? rawItems
                .map(
                  (item) => ObjectInfo.fromJson(item as Map<String, dynamic>),
                )
                .toList(growable: false)
          : const <ObjectInfo>[],
      nextToken: (json['nextToken'] ?? '').toString(),
    );
  }

  final List<ObjectInfo> items;
  final String nextToken;

  bool get hasMore => nextToken.isNotEmpty;
}

class TrashListPage {
  const TrashListPage({required this.items, required this.nextToken});

  factory TrashListPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return TrashListPage(
      items: rawItems is List
          ? rawItems
                .map((item) => TrashItem.fromJson(item as Map<String, dynamic>))
                .toList(growable: false)
          : const <TrashItem>[],
      nextToken: (json['nextToken'] ?? '').toString(),
    );
  }

  final List<TrashItem> items;
  final String nextToken;

  bool get hasMore => nextToken.isNotEmpty;
}
