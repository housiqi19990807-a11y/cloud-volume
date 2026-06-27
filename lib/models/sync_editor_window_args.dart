// Sync editor window arguments cross the multi-window boundary as JSON.
// Carries the initial profile for editing (null for create) and the list
// of account profile names so the sub-window can load configs and buckets.
import 'dart:convert';

import 'package:remote_storage/models/sync_profile.dart';

class SyncEditorWindowArgs {
  const SyncEditorWindowArgs({
    required this.profileNames,
    required this.creatorWindowId,
    this.initialProfileJson,
    this.creatorFrameLeft,
    this.creatorFrameTop,
    this.creatorFrameWidth,
    this.creatorFrameHeight,
  });

  static const String businessId = 'sync_editor';

  final String creatorWindowId;
  final List<String> profileNames;
  final Map<String, dynamic>? initialProfileJson;
  final double? creatorFrameLeft;
  final double? creatorFrameTop;
  final double? creatorFrameWidth;
  final double? creatorFrameHeight;

  SyncProfile? get initialProfile {
    final json = initialProfileJson;
    if (json == null) return null;
    return SyncProfile.fromJson(json);
  }

  factory SyncEditorWindowArgs.fromArguments(String arguments) {
    final json = jsonDecode(arguments) as Map<String, dynamic>;
    return SyncEditorWindowArgs(
      creatorWindowId: json['creatorWindowId'] as String? ?? '',
      profileNames: (json['profileNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      initialProfileJson: json['initialProfile'] as Map<String, dynamic>?,
      creatorFrameLeft: (json['creatorFrameLeft'] as num?)?.toDouble(),
      creatorFrameTop: (json['creatorFrameTop'] as num?)?.toDouble(),
      creatorFrameWidth: (json['creatorFrameWidth'] as num?)?.toDouble(),
      creatorFrameHeight: (json['creatorFrameHeight'] as num?)?.toDouble(),
    );
  }

  String toArguments() {
    return jsonEncode(<String, dynamic>{
      'businessId': businessId,
      'creatorWindowId': creatorWindowId,
      'profileNames': profileNames,
      if (initialProfileJson != null) 'initialProfile': initialProfileJson,
      if (creatorFrameLeft != null) 'creatorFrameLeft': creatorFrameLeft,
      if (creatorFrameTop != null) 'creatorFrameTop': creatorFrameTop,
      if (creatorFrameWidth != null) 'creatorFrameWidth': creatorFrameWidth,
      if (creatorFrameHeight != null) 'creatorFrameHeight': creatorFrameHeight,
    });
  }

  static bool matches(String arguments) {
    if (arguments.trim().isEmpty) return false;
    try {
      final json = jsonDecode(arguments) as Map<String, dynamic>;
      return json['businessId'] == businessId;
    } catch (_) {
      return false;
    }
  }
}
