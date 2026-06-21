import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/core/security/host_fingerprint_store.dart';
import 'package:homelab_tablet/core/security/secure_storage_service.dart';
import 'package:homelab_tablet/features/files/data/sftp_connection_service.dart';
import 'package:homelab_tablet/features/terminal/data/ssh_connection_service.dart';
import 'package:homelab_tablet/features/terminal/domain/models/ssh_connection_models.dart';

void main() {
  group('stored SFTP private key validation', () {
    test('rejects random stored text with a friendly message', () async {
      final service = SftpConnectionService(
        storage: _FakeSecureStorageService(sftpPrivateKey: 'not a private key'),
        fingerprints: HostFingerprintStore(_FakeSecureStorageService()),
      );

      await expectLater(
        service.open(profile: _sftpProfile, onTrustHost: (_) async => true),
        throwsA(
          _friendlyInvalidKeyException(contains('SFTP private key is invalid')),
        ),
      );
    });

    test('rejects stored public keys without leaking parser errors', () async {
      final service = SftpConnectionService(
        storage: _FakeSecureStorageService(
          sftpPrivateKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest user@host',
        ),
        fingerprints: HostFingerprintStore(_FakeSecureStorageService()),
      );

      await expectLater(
        service.testConnection(
          profile: _sftpProfile,
          onTrustHost: (_) async => true,
        ),
        throwsA(
          _friendlyInvalidKeyException(
            allOf(contains('private key file'), contains('.pub file')),
          ),
        ),
      );
    });
  });

  group('stored SSH private key validation', () {
    test('rejects random stored text with a friendly message', () async {
      final service = SshConnectionService(
        storage: _FakeSecureStorageService(sshPrivateKey: 'not a private key'),
        fingerprints: HostFingerprintStore(_FakeSecureStorageService()),
      );

      await expectLater(
        service.testConnection(
          profile: _sshProfile,
          onTrustHost: (_) async => true,
        ),
        throwsA(
          _friendlyInvalidKeyException(contains('SSH private key is invalid')),
        ),
      );
    });
  });
}

Matcher _friendlyInvalidKeyException(Matcher messageMatcher) {
  return isA<SshInvalidPrivateKeyException>()
      .having((error) => error.message, 'message', messageMatcher)
      .having(
        (error) => error.message,
        'message',
        isNot(contains('FormatException')),
      )
      .having(
        (error) => error.message,
        'message',
        isNot(contains('PEM header')),
      );
}

const _sshProfile = ConnectionProfile(
  kind: ConnectionProfileKind.ssh,
  displayName: 'SSH',
  host: 'server.tailnet.ts.net',
  port: 22,
  username: 'tablet_shell',
  hasImportedKey: true,
  storePassphrase: false,
);

const _sftpProfile = ConnectionProfile(
  kind: ConnectionProfileKind.sftp,
  displayName: 'SFTP',
  host: 'server.tailnet.ts.net',
  port: 22,
  username: 'tablet_files',
  hasImportedKey: true,
  storePassphrase: false,
);

class _FakeSecureStorageService extends SecureStorageService {
  _FakeSecureStorageService({this.sshPrivateKey, this.sftpPrivateKey})
    : super(const FlutterSecureStorage());

  final String? sshPrivateKey;
  final String? sftpPrivateKey;
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readSshPrivateKey() async => sshPrivateKey;

  @override
  Future<String?> readSftpPrivateKey() async => sftpPrivateKey;

  @override
  Future<String?> readSshPassphrase() async => null;

  @override
  Future<String?> readSftpPassphrase() async => null;

  @override
  Future<void> clearSshPassphrase() async {}

  @override
  Future<void> clearSftpPassphrase() async {}

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
