class FavoriteLocation {
  const FavoriteLocation({
    required this.hostProfileId,
    required this.remotePath,
    required this.createdAt,
  });

  final String hostProfileId;
  final String remotePath;
  final DateTime createdAt;
}

class RecentDownloadRecord {
  const RecentDownloadRecord({
    required this.hostProfileId,
    required this.fileName,
    required this.remotePath,
    required this.localPath,
    required this.sizeBytes,
    required this.remoteModifiedAt,
    required this.downloadedAt,
  });

  final String hostProfileId;
  final String fileName;
  final String remotePath;
  final String localPath;
  final int? sizeBytes;
  final DateTime? remoteModifiedAt;
  final DateTime downloadedAt;
}

class TransferCheckpoint {
  const TransferCheckpoint({
    required this.hostProfileId,
    required this.remotePath,
    required this.localPath,
    required this.fileSize,
    required this.remoteModifiedAt,
    required this.transferOffset,
    required this.state,
    required this.updatedAt,
  });

  final String hostProfileId;
  final String remotePath;
  final String localPath;
  final int? fileSize;
  final DateTime? remoteModifiedAt;
  final int transferOffset;
  final String state;
  final DateTime updatedAt;
}

class RemoteSearchResult {
  const RemoteSearchResult({
    required this.entryPath,
    required this.name,
    required this.isDirectory,
    required this.depth,
  });

  final String entryPath;
  final String name;
  final bool isDirectory;
  final int depth;
}

class RemoteSearchSnapshot {
  const RemoteSearchSnapshot({
    required this.results,
    required this.truncated,
    required this.cancelled,
    required this.lastVisitedPath,
  });

  final List<RemoteSearchResult> results;
  final bool truncated;
  final bool cancelled;
  final String? lastVisitedPath;
}
