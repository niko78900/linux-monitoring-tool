import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final fileDownloadServiceProvider = Provider<FileDownloadService>(
  (ref) => const FileDownloadService(),
);

class FileDownloadService {
  const FileDownloadService();

  Future<FileDownloadResult> download({
    required SftpClient sftp,
    required String remotePath,
    required String fileName,
    required DownloadCancellationToken cancellationToken,
    required void Function(int transferredBytes, int? totalBytes, String localPath)
    onProgress,
  }) async {
    final downloadsDir = await _ensureDownloadsDirectory();
    final outputFile = await _uniqueDestination(downloadsDir, fileName);
    final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    IOSink? sink;

    try {
      final stat = await remoteFile.stat();
      final totalBytes = stat.size;
      var transferredBytes = 0;

      sink = outputFile.openWrite();
      await for (final chunk in remoteFile.read(length: totalBytes)) {
        if (cancellationToken.isCancelled) {
          throw const DownloadCancelledException();
        }
        sink.add(chunk);
        transferredBytes += chunk.length;
        onProgress(transferredBytes, totalBytes, outputFile.path);
      }
      await sink.flush();
      return FileDownloadResult(
        fileName: fileName,
        localPath: outputFile.path,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes,
      );
    } on DownloadCancelledException {
      await sink?.close();
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      rethrow;
    } finally {
      await sink?.close();
      await remoteFile.close();
    }
  }

  Future<Directory> _ensureDownloadsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final downloads = Directory('${root.path}${Platform.pathSeparator}downloads');
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    return downloads;
  }

  Future<File> _uniqueDestination(Directory directory, String fileName) async {
    final baseName = _sanitizeName(fileName);
    var attempt = 0;
    while (true) {
      final suffix = attempt == 0 ? '' : '-$attempt';
      final candidate = File(
        '${directory.path}${Platform.pathSeparator}${_appendSuffix(baseName, suffix)}',
      );
      if (!await candidate.exists()) {
        return candidate;
      }
      attempt += 1;
    }
  }

  String _sanitizeName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return 'download.bin';
    }
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _appendSuffix(String name, String suffix) {
    final lastDot = name.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == name.length - 1) {
      return '$name$suffix';
    }
    return '${name.substring(0, lastDot)}$suffix${name.substring(lastDot)}';
  }
}

class FileDownloadResult {
  const FileDownloadResult({
    required this.fileName,
    required this.localPath,
    required this.totalBytes,
    required this.transferredBytes,
  });

  final String fileName;
  final String localPath;
  final int? totalBytes;
  final int transferredBytes;
}

class DownloadCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download cancelled';
}
