// Desktop upload expansion tests keep dragged folder uploads preserving shape.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/services/desktop_file_transfer_service_io.dart';

void main() {
  test(
    'localUploadEntries expands directories with relative upload keys',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'remote_storage_upload_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final rootDir = Directory('${tempDir.path}/album');
      final nestedDir = Directory('${rootDir.path}/nested');
      final emptyDir = Directory('${rootDir.path}/empty');
      await nestedDir.create(recursive: true);
      await emptyDir.create(recursive: true);
      await File('${rootDir.path}/cover.txt').writeAsString('cover');
      await File('${nestedDir.path}/track.txt').writeAsString('track');

      final entries = await DesktopFileTransferService.instance
          .localUploadEntries(<String>[rootDir.path]);

      expect(
        entries
            .where((entry) => entry.isDirectory)
            .map((entry) => entry.relativeKey),
        containsAll(<String>['album', 'album/empty', 'album/nested']),
      );
      expect(
        entries
            .where((entry) => !entry.isDirectory)
            .map((entry) => entry.relativeKey),
        containsAll(<String>['album/cover.txt', 'album/nested/track.txt']),
      );
    },
  );
}
