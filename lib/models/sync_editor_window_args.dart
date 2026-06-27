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
  });

  static const String businessId = 'sync_editor';

  final String creatorWindowId;
  final List<String> profileNames;
  final Map<String, dynamic>? initialProfileJson;

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
    );
  }

  String toArguments() {
    return jsonEncode(<String, dynamic>{
      'businessId': businessId,
      'creatorWindowId': creatorWindowId,
      'profileNames': profileNames,
      if (initialProfileJson != null) 'initialProfile': initialProfileJson,
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
