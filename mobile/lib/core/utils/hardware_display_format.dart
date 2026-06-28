String formatOperatingSystemDisplayName(String? rawPlatform) {
  final value = rawPlatform?.trim();
  if (value == null || value.isEmpty) {
    return 'Unknown';
  }

  final lower = value.toLowerCase();
  final debianVersion = RegExp(r'(?:debian|deb)(\d+)').firstMatch(lower);
  if (debianVersion != null) {
    return 'Debian ${debianVersion.group(1)}';
  }

  final debianNamedVersion = RegExp(
    r'debian\s+(?:gnu/linux\s+)?(\d+)',
  ).firstMatch(lower);
  if (debianNamedVersion != null) {
    return 'Debian ${debianNamedVersion.group(1)}';
  }

  if (lower.contains('debian')) {
    return 'Debian';
  }

  final ubuntuVersion = RegExp(r'ubuntu\s+(\d+(?:\.\d+)?)').firstMatch(lower);
  if (ubuntuVersion != null) {
    return 'Ubuntu ${ubuntuVersion.group(1)}';
  }

  if (lower.contains('ubuntu')) {
    return 'Ubuntu';
  }

  return value;
}

String formatKernelDisplayName(String? rawKernel) {
  final value = rawKernel?.trim();
  if (value == null || value.isEmpty) {
    return 'Unknown';
  }

  final version = RegExp(r'(\d+)\.(\d+)').firstMatch(value);
  if (version == null) {
    return value;
  }

  return 'Linux ${version.group(1)}.${version.group(2)}';
}

String formatCpuModelDisplayName(String? rawModel) {
  final value = rawModel?.trim();
  if (value == null || value.isEmpty) {
    return 'Unknown';
  }

  return value
      .replaceFirst(RegExp(r'^\d+(?:st|nd|rd|th)\s+Gen\s+'), '')
      .replaceAll(RegExp(r'\(R\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(TM\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(C\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+CPU\s+@.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
