const _knownAcronyms = {
  'api': 'API',
  'cpu': 'CPU',
  'dns': 'DNS',
  'gpu': 'GPU',
  'hfs': 'HFS',
  'id': 'ID',
  'ip': 'IP',
  'lan': 'LAN',
  'nas': 'NAS',
  'os': 'OS',
  'pc': 'PC',
  'rdp': 'RDP',
  'ssh': 'SSH',
  'sftp': 'SFTP',
  'vm': 'VM',
  'wan': 'WAN',
};

String formatHostDisplayName(String? raw, {String fallback = 'Unknown'}) {
  return _formatDisplayName(raw, fallback: fallback);
}

String formatDeviceDisplayName(String? raw, {String fallback = 'Unknown'}) {
  return _formatDisplayName(raw, fallback: fallback);
}

String _formatDisplayName(String? raw, {required String fallback}) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }

  if (_looksTechnical(value)) {
    return value;
  }

  final words = value
      .split(RegExp(r'[\s_-]+'))
      .where((word) => word.trim().isNotEmpty)
      .map(_formatWord)
      .toList(growable: false);

  return words.isEmpty ? fallback : words.join(' ');
}

bool _looksTechnical(String value) {
  return value.contains('.') ||
      value.contains(':') ||
      value.contains('/') ||
      value.contains('@');
}

String _formatWord(String rawWord) {
  final word = rawWord.trim();
  if (word.isEmpty) {
    return word;
  }

  final lower = word.toLowerCase();
  final acronym = _knownAcronyms[lower];
  if (acronym != null) {
    return acronym;
  }

  return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
}
