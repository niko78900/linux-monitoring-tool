import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/terminal/data/private_key_validation.dart';
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

  test('private key normalization removes BOM and outer whitespace', () {
    final key = validateAndNormalizePrivateKey(
      '\uFEFF \r\n-----BEGIN OPENSSH PRIVATE KEY-----\r\nabc\r\n-----END OPENSSH PRIVATE KEY-----\r\n',
    );

    expect(key, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----\n'));
    expect(key, endsWith('-----END OPENSSH PRIVATE KEY-----'));
  });

  test('public SSH keys are rejected with a friendly message', () {
    expect(
      () => validateAndNormalizePrivateKey(
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest user@host',
      ),
      throwsA(
        isA<PrivateKeyValidationException>().having(
          (error) => error.message,
          'message',
          contains('public key'),
        ),
      ),
    );
  });

  test('random text is rejected before storage', () {
    expect(
      () => validateAndNormalizePrivateKey('not a private key'),
      throwsA(
        isA<PrivateKeyValidationException>().having(
          (error) => error.message,
          'message',
          contains('private SSH key'),
        ),
      ),
    );
  });
}
