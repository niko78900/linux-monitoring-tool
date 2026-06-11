import 'secure_storage_service.dart';

class HostFingerprintStore {
  HostFingerprintStore(this._storage);

  final SecureStorageService _storage;

  Future<String?> readTrustedFingerprint(String host, int port) {
    return _storageKey(host, port).then(_storage.read);
  }

  Future<void> trustFingerprint(
    String host,
    int port,
    String fingerprint,
  ) async {
    final key = await _storageKey(host, port);
    await _storage.write(key, fingerprint);
  }

  Future<void> resetTrustedFingerprint(String host, int port) async {
    final key = await _storageKey(host, port);
    await _storage.delete(key);
  }

  Future<String> _storageKey(String host, int port) async {
    return 'trusted_host_fingerprint.${host.trim().toLowerCase()}.$port';
  }
}
