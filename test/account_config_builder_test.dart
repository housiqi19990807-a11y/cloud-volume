// Account config construction tests protect secret-preservation edit semantics.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/cloud_storage_account_draft.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/utils/account_config_builder.dart';

CloudStorageAccountDraft s3Draft({String secretKey = ''}) {
  return CloudStorageAccountDraft(
    storageType: StorageType.s3,
    name: 'demo',
    mappedBucketName: 'demo',
    endpoint: 'https://s3.example.test',
    region: 'auto',
    accessKey: 'next-ak',
    secretKey: secretKey,
    usePathStyle: true,
    webdavUsername: '',
    webdavPassword: '',
    ftpUsername: '',
    ftpPassword: '',
  );
}

void main() {
  test('blank edited secret keeps the stored secret', () {
    final existing = RemoteStorageConfig.empty().copyWith(
      secretAccessKey: 'existing-sk',
      hasSecretAccessKey: true,
    );

    final config = buildAccountConfig(s3Draft(), existing: existing);

    expect(config.secretAccessKey, 'existing-sk');
    expect(config.hasSecretAccessKey, isTrue);
  });

  test('entered edited secret replaces the stored secret', () {
    final existing = RemoteStorageConfig.empty().copyWith(
      secretAccessKey: 'existing-sk',
      hasSecretAccessKey: true,
    );

    final config = buildAccountConfig(
      s3Draft(secretKey: 'replacement-sk'),
      existing: existing,
    );

    expect(config.secretAccessKey, 'replacement-sk');
  });
}
