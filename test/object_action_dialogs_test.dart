// Object action dialog helpers keep selected folders separate from object keys.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';

void main() {
  const file = ObjectInfo(key: 'source/report.txt', size: 10, isDir: false);

  test('builds a target key from the selected remote directory', () {
    expect(
      objectTargetPathInDirectory('archive/2026/', file),
      'archive/2026/report.txt',
    );
    expect(objectTargetPathInDirectory('', file), 'report.txt');
  });
}
