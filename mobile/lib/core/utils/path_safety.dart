String normalizeVirtualPath(String root, String path) {
  final safeRoot = _normalizeRoot(root);
  final input = path.trim().isEmpty ? safeRoot : path.trim();
  final rawSegments = input.split('/');
  final segments = <String>[];
  for (final segment in rawSegments) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  final normalized = '/${segments.join('/')}';
  if (normalized == safeRoot || normalized.startsWith('$safeRoot/')) {
    return normalized;
  }
  return safeRoot;
}

String _normalizeRoot(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '/';
  }
  final withSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return withSlash.replaceAll(RegExp(r'/+$'), '');
}
