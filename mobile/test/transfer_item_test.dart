import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/files/domain/models/transfer_item.dart';

void main() {
  test('transfer progress handles missing totals', () {
    const queued = TransferItem(
      id: '1',
      fileName: 'backup.tar',
      remotePath: '/warm/backup.tar',
      localPath: null,
      totalBytes: null,
      transferredBytes: 512,
      state: TransferState.downloading,
      errorMessage: null,
    );

    expect(queued.progress, isNull);

    final updated = queued.copyWith(totalBytes: 1024, transferredBytes: 256);

    expect(updated.progress, 0.25);
  });
}
