import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/security/host_fingerprint_store.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../terminal/data/private_key_validation.dart';
import '../../terminal/domain/models/ssh_connection_models.dart';

typedef SftpHostTrustPrompt = Future<bool> Function(SshHostFingerprint hostKey);
typedef SftpPassphrasePrompt = Future<PassphrasePromptResult?> Function();

final sftpConnectionServiceProvider = Provider<SftpConnectionClient>(
  (ref) => SftpConnectionService(
    storage: ref.watch(secureStorageServiceProvider),
    fingerprints: ref.watch(hostFingerprintStoreProvider),
  ),
);

abstract interface class SftpConnectionClient {
  Future<void> testConnection({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  });

  Future<SftpSessionConnection> open({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  });

  Future<String?> readTrustedFingerprint(ConnectionProfile profile);

  Future<void> resetTrustedFingerprint(ConnectionProfile profile);
}

class SftpConnectionService implements SftpConnectionClient {
  SftpConnectionService({
    required SecureStorageService storage,
    required HostFingerprintStore fingerprints,
  }) : _storage = storage,
       _fingerprints = fingerprints;

  final SecureStorageService _storage;
  final HostFingerprintStore _fingerprints;

  @override
  Future<void> testConnection({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  }) async {
    final connection = await open(
      profile: profile,
      onTrustHost: onTrustHost,
      onPassphraseRequired: onPassphraseRequired,
    );
    await connection.close();
  }

  @override
  Future<SftpSessionConnection> open({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  }) async {
    final host = profile.host.trim();
    final username = profile.username.trim();
    if (host.isEmpty || username.isEmpty || profile.port <= 0) {
      throw const SshProfileIncompleteException();
    }

    final privateKey = await _storage.readSftpPrivateKey();
    if (privateKey == null || privateKey.trim().isEmpty) {
      throw const SshPrivateKeyMissingException();
    }

    final normalizedPrivateKey = _validateStoredPrivateKey(privateKey);
    final identities = await _loadIdentities(
      normalizedPrivateKey,
      readStoredPassphrase: _storage.readSftpPassphrase,
      clearStoredPassphrase: _storage.clearSftpPassphrase,
      onPassphraseRequired: onPassphraseRequired,
    );

    SshHostKeyChangedException? fingerprintMismatch;
    var hostRejected = false;

    final socket = await SSHSocket.connect(host, profile.port);
    final client = SSHClient(
      socket,
      username: username,
      identities: identities,
      onVerifyHostKey: (algorithm, fingerprintBytes) async {
        final fingerprint = SshHostFingerprint(
          algorithm: algorithm,
          fingerprint: _formatFingerprint(fingerprintBytes),
        );
        final stored = await _fingerprints.readTrustedFingerprint(
          profile.host,
          profile.port,
        );
        if (stored == null || stored.isEmpty) {
          final trusted = await onTrustHost(fingerprint);
          if (trusted) {
            await _fingerprints.trustFingerprint(
              profile.host,
              profile.port,
              fingerprint.displayValue,
            );
            return true;
          }
          hostRejected = true;
          return false;
        }
        if (stored == fingerprint.displayValue) {
          return true;
        }
        fingerprintMismatch = SshHostKeyChangedException(
          host: host,
          port: profile.port,
          expectedFingerprint: stored,
          actualFingerprint: fingerprint.displayValue,
        );
        return false;
      },
    );

    try {
      await client.authenticated;
      final sftp = await client.sftp();
      return DartSftpSessionConnection(client: client, sftp: sftp);
    } catch (_) {
      client.close();
      if (fingerprintMismatch != null) {
        throw fingerprintMismatch!;
      }
      if (hostRejected) {
        throw const SshHostKeyRejectedException();
      }
      rethrow;
    }
  }

  @override
  Future<String?> readTrustedFingerprint(ConnectionProfile profile) {
    if (!profile.isConfigured) {
      return Future.value(null);
    }
    return _fingerprints.readTrustedFingerprint(profile.host, profile.port);
  }

  @override
  Future<void> resetTrustedFingerprint(ConnectionProfile profile) {
    if (!profile.isConfigured) {
      return Future.value();
    }
    return _fingerprints.resetTrustedFingerprint(profile.host, profile.port);
  }

  Future<List<SSHKeyPair>> _loadIdentities(
    String privateKey, {
    SftpPassphrasePrompt? onPassphraseRequired,
    required Future<String?> Function() readStoredPassphrase,
    required Future<void> Function() clearStoredPassphrase,
  }) async {
    if (!_isEncryptedPem(privateKey)) {
      return _parsePrivateKey(privateKey, null);
    }

    final storedPassphrase = await readStoredPassphrase();
    final passphrase = storedPassphrase?.trim();
    if (passphrase != null && passphrase.isNotEmpty) {
      try {
        return _parsePrivateKey(privateKey, passphrase);
      } on SshInvalidPrivateKeyException {
        await clearStoredPassphrase();
        if (onPassphraseRequired == null) {
          rethrow;
        }
      }
    }

    final prompted = await onPassphraseRequired?.call();
    final normalized = prompted?.passphrase.trim();
    if (normalized == null || normalized.isEmpty) {
      throw const SshPassphraseRequiredException();
    }
    return _parsePrivateKey(privateKey, normalized);
  }

  List<SSHKeyPair> _parsePrivateKey(String pem, String? passphrase) {
    try {
      return SSHKeyPair.fromPem(pem, passphrase);
    } catch (error) {
      throw SshInvalidPrivateKeyException.sftp(cause: error);
    }
  }

  String _validateStoredPrivateKey(String privateKey) {
    try {
      return validateAndNormalizePrivateKey(privateKey);
    } catch (error) {
      throw SshInvalidPrivateKeyException.sftp(cause: error);
    }
  }

  bool _isEncryptedPem(String privateKey) {
    try {
      return SSHKeyPair.isEncryptedPem(privateKey);
    } catch (error) {
      throw SshInvalidPrivateKeyException.sftp(cause: error);
    }
  }

  String _formatFingerprint(List<int> value) {
    final buffer = StringBuffer();
    for (var index = 0; index < value.length; index += 1) {
      if (index > 0) {
        buffer.write(':');
      }
      buffer.write(value[index].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

abstract interface class SftpSessionConnection {
  SftpClient get sftp;

  Future<void> close();
}

class DartSftpSessionConnection implements SftpSessionConnection {
  DartSftpSessionConnection({required this.client, required this.sftp});

  final SSHClient client;

  @override
  final SftpClient sftp;

  @override
  Future<void> close() async {
    sftp.close();
    client.close();
  }
}
