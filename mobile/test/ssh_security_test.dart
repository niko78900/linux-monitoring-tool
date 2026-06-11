import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/terminal/domain/models/ssh_connection_models.dart';

void main() {
  test('host fingerprint mismatch instructs the operator to reset trust', () {
    final error = SshHostKeyChangedException(
      host: 'server.tailnet.ts.net',
      port: 22,
      expectedFingerprint: 'ssh-ed25519 aa:bb:cc',
      actualFingerprint: 'ssh-ed25519 dd:ee:ff',
    );

    expect(error.expectedFingerprint, 'ssh-ed25519 aa:bb:cc');
    expect(error.actualFingerprint, 'ssh-ed25519 dd:ee:ff');
    expect(error.message, contains('Reset trusted fingerprint in Settings'));
  });
}
