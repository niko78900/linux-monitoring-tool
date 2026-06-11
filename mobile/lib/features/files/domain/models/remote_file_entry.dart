class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.isSymbolicLink,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isSymbolicLink;
  final int? sizeBytes;
  final DateTime? modifiedAt;
}
