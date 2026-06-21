import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/security/host_fingerprint_store.dart';
import '../../../core/security/secure_storage_service.dart';
import 'private_key_validation.dart';
import '../domain/models/ssh_connection_models.dart';

typedef SshHostTrustPrompt = Future<bool> Function(SshHostFingerprint hostKey);
typedef SshPassphrasePrompt = Future<PassphrasePromptResult?> Function();

final sshConnectionServiceProvider = Provider<SshConnectionClient>(
  (ref) => SshConnectionService(
    storage: ref.watch(secureStorageServiceProvider),
    fingerprints: ref.watch(hostFingerprintStoreProvider),
  ),
);

abstract interface class SshConnectionClient {
  Future<void> testConnection({
    required ConnectionProfile profile,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  });

  Future<SshShellConnection> openShell({
    required ConnectionProfile profile,
    required int width,
    required int height,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  });

  Future<String?> readTrustedFingerprint(ConnectionProfile profile);

  Future<void> resetTrustedFingerprint(ConnectionProfile profile);
}

class SshConnectionService implements SshConnectionClient {
  SshConnectionService({
    required SecureStorageService storage,
    required HostFingerprintStore fingerprints,
  }) : _storage = storage,
       _fingerprints = fingerprints;

  final SecureStorageService _storage;
  final HostFingerprintStore _fingerprints;

  @override
  Future<void> testConnection({
    required ConnectionProfile profile,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  }) async {
    final client = await _openClient(
      profile: profile,
      readPrivateKey: _storage.readSshPrivateKey,
      readStoredPassphrase: _storage.readSshPassphrase,
      clearStoredPassphrase: _storage.clearSshPassphrase,
      onTrustHost: onTrustHost,
      onPassphraseRequired: onPassphraseRequired,
    );
    try {
      await client.authenticated;
    } finally {
      client.close();
    }
  }

  @override
  Future<SshShellConnection> openShell({
    required ConnectionProfile profile,
    required int width,
    required int height,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  }) async {
    final client = await _openClient(
      profile: profile,
      readPrivateKey: _storage.readSshPrivateKey,
      readStoredPassphrase: _storage.readSshPassphrase,
      clearStoredPassphrase: _storage.clearSshPassphrase,
      onTrustHost: onTrustHost,
      onPassphraseRequired: onPassphraseRequired,
    );

    try {
      await client.authenticated;
      final session = await client.shell(
        pty: SSHPtyConfig(width: width, height: height),
      );
      return DartSshShellConnection(client: client, session: session);
    } catch (_) {
      client.close();
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

  Future<SSHClient> _openClient({
    required ConnectionProfile profile,
    required Future<String?> Function() readPrivateKey,
    required Future<String?> Function() readStoredPassphrase,
    required Future<void> Function() clearStoredPassphrase,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  }) async {
    final host = profile.host.trim();
    final username = profile.username.trim();
    if (host.isEmpty || username.isEmpty || profile.port <= 0) {
      throw const SshProfileIncompleteException();
    }

    final privateKey = await readPrivateKey();
    if (privateKey == null || privateKey.trim().isEmpty) {
      throw const SshPrivateKeyMissingException();
    }

    final normalizedPrivateKey = _validateStoredPrivateKey(privateKey);
    final identities = await _loadIdentities(
      normalizedPrivateKey,
      readStoredPassphrase: readStoredPassphrase,
      clearStoredPassphrase: clearStoredPassphrase,
      onPassphraseRequired: onPassphraseRequired,
    );

    SshHostKeyChangedException? fingerprintMismatch;
    var hostRejected = false;

    try {
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
      return client;
    } catch (_) {
      if (fingerprintMismatch != null) {
        throw fingerprintMismatch!;
      }
      if (hostRejected) {
        throw const SshHostKeyRejectedException();
      }
      rethrow;
    }
  }

  Future<List<SSHKeyPair>> _loadIdentities(
    String privateKey, {
    SshPassphrasePrompt? onPassphraseRequired,
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
      throw SshInvalidPrivateKeyException.ssh(cause: error);
    }
  }

  String _validateStoredPrivateKey(String privateKey) {
    try {
      return validateAndNormalizePrivateKey(privateKey);
    } catch (error) {
      throw SshInvalidPrivateKeyException.ssh(cause: error);
    }
  }

  bool _isEncryptedPem(String privateKey) {
    try {
      return SSHKeyPair.isEncryptedPem(privateKey);
    } catch (error) {
      throw SshInvalidPrivateKeyException.ssh(cause: error);
    }
  }

  String _formatFingerprint(Uint8List value) {
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

abstract interface class SshShellConnection {
  Stream<Uint8List> get stdout;

  Stream<Uint8List> get stderr;

  Future<void> get done;

  void resizeTerminal(int width, int height, int pixelWidth, int pixelHeight);

  void write(Uint8List data);

  Future<void> close();
}

class DartSshShellConnection implements SshShellConnection {
  DartSshShellConnection({required this.client, required this.session});

  final SSHClient client;
  final SSHSession session;

  @override
  Stream<Uint8List> get stdout => session.stdout;

  @override
  Stream<Uint8List> get stderr => session.stderr;

  @override
  Future<void> get done => session.done;

  @override
  void resizeTerminal(int width, int height, int pixelWidth, int pixelHeight) {
    session.resizeTerminal(width, height, pixelWidth, pixelHeight);
  }

  @override
  void write(Uint8List data) {
    session.write(data);
  }

  @override
  Future<void> close() async {
    session.close();
    client.close();
    try {
      await session.done.timeout(const Duration(milliseconds: 250));
    } on TimeoutException {
      // Transport shutdown already closed the session.
    }
  }
}
