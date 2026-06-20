import '../../../core/errors/app_exception.dart';

const _privateKeyHeaders = [
  '-----BEGIN OPENSSH PRIVATE KEY-----',
  '-----BEGIN RSA PRIVATE KEY-----',
  '-----BEGIN DSA PRIVATE KEY-----',
  '-----BEGIN EC PRIVATE KEY-----',
  '-----BEGIN PRIVATE KEY-----',
];

const _publicKeyPrefixes = [
  'ssh-ed25519 ',
  'ssh-rsa ',
  'ssh-dss ',
  'ecdsa-sha2-',
  'sk-ssh-ed25519@openssh.com ',
  'sk-ecdsa-sha2-nistp256@openssh.com ',
];

String validateAndNormalizePrivateKey(String contents) {
  final normalized = normalizePrivateKey(contents);
  final firstLine = normalized.split('\n').first.trim();
  final lowerFirstLine = firstLine.toLowerCase();

  if (_publicKeyPrefixes.any(lowerFirstLine.startsWith) ||
      lowerFirstLine.startsWith('---- begin ssh2 public key ----')) {
    throw const PrivateKeyValidationException(
      'This is a public key. Import the private key file, not the .pub file.',
    );
  }

  final hasPrivateHeader = _privateKeyHeaders.any(normalized.startsWith);
  if (!hasPrivateHeader) {
    throw const PrivateKeyValidationException(
      'This does not look like a private SSH key. Import the private key file, not the .pub file.',
    );
  }

  return normalized;
}

String normalizePrivateKey(String contents) {
  var normalized = contents.replaceFirst('\uFEFF', '');
  normalized = normalized.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized.trim();
}

class PrivateKeyValidationException extends AppException {
  const PrivateKeyValidationException(super.message);
}
