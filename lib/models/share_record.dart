// Share record models keep presigned-link metadata separate from file listings.

class ShareRecord {
  const ShareRecord({
    required this.id,
    required this.bucket,
    required this.key,
    required this.name,
    required this.url,
    required this.expiresAt,
    required this.durationSec,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ShareRecord.fromJson(Map<String, dynamic> json) {
    return ShareRecord(
      id: (json['id'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      durationSec: (json['durationSec'] ?? 0) as int,
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }

  final String id;
  final String bucket;
  final String key;
  final String name;
  final String url;
  final String expiresAt;
  final int durationSec;
  final String createdAt;
  final String updatedAt;

  DateTime? get expiresAtDateTime => DateTime.tryParse(expiresAt)?.toLocal();
}
