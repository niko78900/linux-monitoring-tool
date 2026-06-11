import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/security/host_fingerprint_store.dart';
import 'package:homelab_tablet/core/security/secure_storage_service.dart';

void main() {
  test('stores, reads, and resets trusted host fingerprints', () async {
    final storage = _InMemorySecureStorageService();
    final store = HostFingerprintStore(storage);

    expect(
      await store.readTrustedFingerprint('Server.Tailnet.ts.net', 22),
      isNull,
    );

    await store.trustFingerprint(
      'Server.Tailnet.ts.net',
      22,
      'ssh-ed25519 aa:bb:cc',
    );

    expect(
      await store.readTrustedFingerprint('server.tailnet.ts.net', 22),
      'ssh-ed25519 aa:bb:cc',
    );

    await store.resetTrustedFingerprint('server.tailnet.ts.net', 22);

    expect(
      await store.readTrustedFingerprint('server.tailnet.ts.net', 22),
      isNull,
    );
  });
}

class _InMemorySecureStorageService extends SecureStorageService {
  _InMemorySecureStorageService() : super(const FlutterSecureStorage());

  final Map<String, String> _values = <String, String>{};

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
