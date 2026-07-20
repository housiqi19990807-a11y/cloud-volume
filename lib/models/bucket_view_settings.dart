// Per-account bucket visibility and presentation settings.

class BucketViewSettings {
  const BucketViewSettings({this.displayName = '', this.rootPrefix = ''});

  factory BucketViewSettings.fromJson(Map<String, dynamic> json) {
    return BucketViewSettings(
      displayName: (json['displayName'] ?? json['display_name'] ?? '')
          .toString(),
      rootPrefix: (json['rootPrefix'] ?? json['root_prefix'] ?? '').toString(),
    );
  }

  final String displayName;
  final String rootPrefix;

  BucketViewSettings copyWith({String? displayName, String? rootPrefix}) {
    return BucketViewSettings(
      displayName: displayName ?? this.displayName,
      rootPrefix: rootPrefix ?? this.rootPrefix,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'displayName': displayName.trim(),
    'rootPrefix': rootPrefix.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
  };
}

Map<String, BucketViewSettings> bucketViewsMapFromJson(Object? value) {
  if (value is! Map) return const <String, BucketViewSettings>{};
  final result = <String, BucketViewSettings>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty || entry.value is! Map) continue;
    result[key] = BucketViewSettings.fromJson(
      Map<String, dynamic>.from(entry.value as Map),
    );
  }
  return result;
}
