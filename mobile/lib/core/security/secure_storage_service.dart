import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(const FlutterSecureStorage()),
);

class SecureStorageService {
  SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  static const _controlTokenKey = 'control_api_token';
  static const _sshPrivateKeyKey = 'ssh_private_key';
  static const _sshPassphraseKey = 'ssh_key_passphrase';
  static const _sftpPrivateKeyKey = 'sftp_private_key';
  static const _sftpPassphraseKey = 'sftp_key_passphrase';

  Future<String?> readControlToken() => _storage.read(key: _controlTokenKey);

  Future<void> writeControlToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _controlTokenKey);
      return;
    }
    await _storage.write(key: _controlTokenKey, value: trimmed);
  }

  Future<void> clearControlToken() => _storage.delete(key: _controlTokenKey);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> writeSshPrivateKey(String value) =>
      _storage.write(key: _sshPrivateKeyKey, value: value);

  Future<String?> readSshPrivateKey() => _storage.read(key: _sshPrivateKeyKey);

  Future<void> clearSshPrivateKey() => _storage.delete(key: _sshPrivateKeyKey);

  Future<void> writeSshPassphrase(String value) =>
      _storage.write(key: _sshPassphraseKey, value: value);

  Future<String?> readSshPassphrase() => _storage.read(key: _sshPassphraseKey);

  Future<void> clearSshPassphrase() => _storage.delete(key: _sshPassphraseKey);

  Future<void> writeSftpPrivateKey(String value) =>
      _storage.write(key: _sftpPrivateKeyKey, value: value);

  Future<String?> readSftpPrivateKey() =>
      _storage.read(key: _sftpPrivateKeyKey);

  Future<void> clearSftpPrivateKey() =>
      _storage.delete(key: _sftpPrivateKeyKey);

  Future<void> writeSftpPassphrase(String value) =>
      _storage.write(key: _sftpPassphraseKey, value: value);

  Future<String?> readSftpPassphrase() =>
      _storage.read(key: _sftpPassphraseKey);

  Future<void> clearSftpPassphrase() =>
      _storage.delete(key: _sftpPassphraseKey);
}
