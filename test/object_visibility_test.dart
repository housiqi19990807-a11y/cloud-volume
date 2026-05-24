// Visibility tests lock down the default dot-file filtering behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/utils/object_visibility.dart';

void main() {
  test('filterVisibleObjects hides dot files and dot directories', () {
    final filtered = filterVisibleObjects(<ObjectInfo>[
      const ObjectInfo(key: '.env', size: 12, isDir: false),
      const ObjectInfo(key: 'docs/.cache/', size: 0, isDir: true),
      const ObjectInfo(key: 'docs/report.pdf', size: 24, isDir: false),
      const ObjectInfo(key: 'visible/', size: 0, isDir: true),
    ], hideDotFiles: true);

    expect(filtered.map((item) => item.displayName), <String>[
      'report.pdf',
      'visible',
    ]);
  });

  test(
    'filterVisibleObjects keeps all entries when dot filtering is disabled',
    () {
      final filtered = filterVisibleObjects(<ObjectInfo>[
        const ObjectInfo(key: '.env', size: 12, isDir: false),
        const ObjectInfo(key: 'visible.txt', size: 24, isDir: false),
      ], hideDotFiles: false);

      expect(filtered.map((item) => item.displayName), <String>[
        '.env',
        'visible.txt',
      ]);
    },
  );
}
