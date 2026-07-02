// Account editor window arguments cross the multi-window boundary as JSON.
// Carries the existing config for editing (null for create) and the profile
// name so the sub-window can save back to the same profile key.

import 'dart:convert';

import 'package:remote_storage/models/remote_storage_config.dart';

class AccountEditorWindowArgs {
  const AccountEditorWindowArgs({
    required this.creatorWindowId,
    this.initialConfigJson,
    this.profileName,
    this.editing = false,
    this.creatorFrameLeft,
    this.creatorFrameTop,
    this.creatorFrameWidth,
    this.creatorFrameHeight,
  });

  static const String businessId = 'account_editor';

  final String creatorWindowId;
  final Map<String, dynamic>? initialConfigJson;
  final String? profileName;
  final bool editing;
  final double? creatorFrameLeft;
  final double? creatorFrameTop;
  final double? creatorFrameWidth;
  final double? creatorFrameHeight;

  RemoteStorageConfig? get initialConfig {
    final json = initialConfigJson;
    if (json == null) return null;
    return RemoteStorageConfig.fromJson(json);
  }

  factory AccountEditorWindowArgs.fromArguments(String arguments) {
    final json = jsonDecode(arguments) as Map<String, dynamic>;
    return AccountEditorWindowArgs(
      creatorWindowId: json['creatorWindowId'] as String? ?? '',
      initialConfigJson: json['initialConfig'] as Map<String, dynamic>?,
      profileName: json['profileName'] as String?,
      editing: json['editing'] as bool? ?? false,
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
      if (initialConfigJson != null) 'initialConfig': initialConfigJson,
      if (profileName != null) 'profileName': profileName,
      'editing': editing,
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
