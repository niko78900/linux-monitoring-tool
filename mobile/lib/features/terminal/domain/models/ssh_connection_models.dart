import '../../../../core/errors/app_exception.dart';

class SshHostFingerprint {
  const SshHostFingerprint({
    required this.algorithm,
    required this.fingerprint,
  });

  final String algorithm;
  final String fingerprint;

  String get displayValue => '$algorithm $fingerprint';
}

class PassphrasePromptResult {
  const PassphrasePromptResult({
    required this.passphrase,
    required this.remember,
  });

  final String passphrase;
  final bool remember;
}

class SshHostKeyChangedException extends AppException {
  SshHostKeyChangedException({
    required this.host,
    required this.port,
    required this.expectedFingerprint,
    required this.actualFingerprint,
  }) : super(
         'Host fingerprint changed for $host:$port. Reset trusted fingerprint in Settings before reconnecting.',
       );

  final String host;
  final int port;
  final String expectedFingerprint;
  final String actualFingerprint;
}

class SshHostKeyRejectedException extends AppException {
  const SshHostKeyRejectedException()
    : super('Host fingerprint was not trusted.');
}

class SshPrivateKeyMissingException extends AppException {
  const SshPrivateKeyMissingException()
    : super('Import a private key before connecting.');
}

class SshProfileIncompleteException extends AppException {
  const SshProfileIncompleteException()
    : super('Complete the SSH host, port, and username before connecting.');
}

class SshPassphraseRequiredException extends AppException {
  const SshPassphraseRequiredException()
    : super('Enter the SSH key passphrase to continue.');
}

class SshInvalidPrivateKeyException extends AppException {
  const SshInvalidPrivateKeyException({
    String message = 'The imported private key could not be opened.',
    Object? cause,
  }) : super(message, cause: cause);

  const SshInvalidPrivateKeyException.ssh({Object? cause})
    : super(
        'The imported SSH private key is invalid. Remove it and import the private key file again, not the .pub file.',
        cause: cause,
      );

  const SshInvalidPrivateKeyException.sftp({Object? cause})
    : super(
        'The imported SFTP private key is invalid. Remove it and import the private key file again, not the .pub file.',
        cause: cause,
      );
}
