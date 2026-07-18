// Transfer completion tests keep locally finalized progress internally consistent.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/state/transfer_queue.dart';

void main() {
  setUp(TransferQueue.instance.resetForTest);
  tearDown(TransferQueue.instance.resetForTest);

  test('markTaskDone completes both byte and item progress', () {
    final queue = TransferQueue.instance;
    final task = queue.startTask(
      kind: TransferKind.delete,
      bucket: 'bucket-a',
      key: 'folder/',
      localPath: '',
    );
    task.totalBytes = 4 * 1024 * 1024;
    task.bytesCompleted = task.totalBytes;
    task.totalItems = 20;
    task.itemsCompleted = 10;

    queue.markTaskDone(task.id);

    expect(task.status, TransferStatus.done);
    expect(task.bytesCompleted, task.totalBytes);
    expect(task.itemsCompleted, task.totalItems);
  });
}
