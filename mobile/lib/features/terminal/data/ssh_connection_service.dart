import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/security/host_fingerprint_store.dart';
import '../../../core/security/secure_storage_service.dart';
import '../domain/models/ssh_connection_models.dart';

typedef SshHostTrustPrompt = Future<bool> Function(SshHostFingerprint hostKey);
typedef SshPassphrasePrompt = Future<String?> Function();

final sshConnectionServiceProvider = Provider<SshConnectionService>(
  (ref) => SshConnectionService(
    storage: ref.watch(secureStorageServiceProvider),
    fingerprints: ref.watch(hostFingerprintStoreProvider),
  ),
);

class SshConnectionService {
  SshConnectionService({
    required SecureStorageService storage,
    required HostFingerprintStore fingerprints,
  }) : _storage = storage,
       _fingerprints = fingerprints;

  final SecureStorageService _storage;
  final HostFingerprintStore _fingerprints;

  Future<void> testConnection({
    required ConnectionProfile profile,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  }) async {
    final client = await _openClient(
      profile: profile,
      readPrivateKey: _storage.readSshPrivateKey,
      readStoredPassphrase: _storage.readSshPassphrase,
      onTrustHost: onTrustHost,
      onPassphraseRequired: onPassphraseRequired,
    );
    try {
      await client.authenticated;
    } finally {
      client.close();
    }
  }

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
      onTrustHost: onTrustHost,
      onPassphraseRequired: onPassphraseRequired,
    );

    try {
      await client.authenticated;
      final session = await client.shell(
        pty: SSHPtyConfig(width: width, height: height),
      );
      return SshShellConnection(client: client, session: session);
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  Future<String?> readTrustedFingerprint(ConnectionProfile profile) {
    if (!profile.isConfigured) {
      return Future.value(null);
    }
    return _fingerprints.readTrustedFingerprint(profile.host, profile.port);
  }

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

    final passphrase = await _resolvePassphrase(
      privateKey,
      await readStoredPassphrase(),
      onPassphraseRequired,
    );
    final identities = _parsePrivateKey(privateKey, passphrase);

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

  Future<String?> _resolvePassphrase(
    String privateKey,
    String? storedPassphrase,
    SshPassphrasePrompt? onPassphraseRequired,
  ) async {
    if (!SSHKeyPair.isEncryptedPem(privateKey)) {
      return null;
    }

    final passphrase = storedPassphrase?.trim();
    if (passphrase != null && passphrase.isNotEmpty) {
      return passphrase;
    }

    final prompted = await onPassphraseRequired?.call();
    final normalized = prompted?.trim();
    if (normalized == null || normalized.isEmpty) {
      throw const SshPassphraseRequiredException();
    }
    return normalized;
  }

  List<SSHKeyPair> _parsePrivateKey(String pem, String? passphrase) {
    try {
      return SSHKeyPair.fromPem(pem, passphrase);
    } catch (error) {
      throw SshInvalidPrivateKeyException(cause: error);
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

class SshShellConnection {
  SshShellConnection({
    required this.client,
    required this.session,
  });

  final SSHClient client;
  final SSHSession session;

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
