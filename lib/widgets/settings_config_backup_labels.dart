// Shared label helpers for configuration backup UI surfaces.
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/utils/transfer_format.dart';

String configBackupSnapshotPrimaryLabel(ConfigBackupSnapshot snapshot) {
  final createdAt = DateTime.tryParse(snapshot.createdAt)?.toLocal();
  if (createdAt != null) {
    final y = createdAt.year.toString().padLeft(4, '0');
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    final hh = createdAt.hour.toString().padLeft(2, '0');
    final mm = createdAt.minute.toString().padLeft(2, '0');
    final ss = createdAt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }
  if (snapshot.displayName.trim().isNotEmpty) {
    return snapshot.displayName.trim();
  }
  return snapshot.key;
}

String configBackupSnapshotSecondaryLabel(ConfigBackupSnapshot snapshot) {
  final parts = <String>[];
  if (snapshot.size > 0) {
    parts.add(formatBytes(snapshot.size));
  }
  final name = snapshot.displayName.trim();
  if (name.isNotEmpty && name != configBackupSnapshotPrimaryLabel(snapshot)) {
    parts.add(name);
  }
  return parts.join(' · ');
}

String configBackupFriendlyError(Object error) {
  final text = error.toString().trim();
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length).trim();
    }
  }
  return text;
}

