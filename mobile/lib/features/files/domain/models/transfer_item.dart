enum TransferState {
  queued,
  downloading,
  completed,
  failed,
  cancelled,
}

class TransferItem {
  const TransferItem({
    required this.id,
    required this.fileName,
    required this.remotePath,
    required this.localPath,
    required this.totalBytes,
    required this.transferredBytes,
    required this.state,
    required this.errorMessage,
  });

  final String id;
  final String fileName;
  final String remotePath;
  final String? localPath;
  final int? totalBytes;
  final int transferredBytes;
  final TransferState state;
  final String? errorMessage;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return transferredBytes / total;
  }

  TransferItem copyWith({
    String? id,
    String? fileName,
    String? remotePath,
    String? localPath,
    int? totalBytes,
    int? transferredBytes,
    TransferState? state,
    String? errorMessage,
    bool clearLocalPath = false,
    bool clearError = false,
  }) {
    return TransferItem(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      remotePath: remotePath ?? this.remotePath,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      state: state ?? this.state,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
