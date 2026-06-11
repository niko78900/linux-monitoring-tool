import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models/file_browser_models.dart';
import 'file_metadata_store.dart';

final fileDownloadServiceProvider = Provider<FileDownloadService>(
  (ref) => FileDownloadService(metadataStore: ref.watch(fileMetadataStoreProvider)),
);

class FileDownloadService {
  FileDownloadService({required FileMetadataStore metadataStore})
    : _metadataStore = metadataStore;

  final FileMetadataStore _metadataStore;

  Future<FileDownloadResult> download({
    required SftpClient sftp,
    required String hostProfileId,
    required String remotePath,
    required String fileName,
    required DateTime? remoteModifiedAt,
    required DownloadCancellationToken cancellationToken,
    required void Function(int transferredBytes, int? totalBytes, String localPath)
    onProgress,
  }) async {
    final downloadsDir = await _ensureDownloadsDirectory();
    final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    IOSink? sink;

    try {
      final stat = await remoteFile.stat();
      final totalBytes = stat.size;
      final checkpoint = await _metadataStore.readTransferCheckpoint(
        hostProfileId,
        remotePath,
      );
      final canResume =
          checkpoint != null &&
          checkpoint.fileSize == totalBytes &&
          checkpoint.remoteModifiedAt == remoteModifiedAt &&
          await File(checkpoint.localPath).exists();
      final outputFile = canResume
          ? File(checkpoint.localPath)
          : await _partDestination(downloadsDir, fileName);
      var transferredBytes = canResume ? checkpoint.transferOffset : 0;

      sink = outputFile.openWrite(
        mode: canResume ? FileMode.append : FileMode.writeOnly,
      );
      await _metadataStore.upsertTransferCheckpoint(
        TransferCheckpoint(
          hostProfileId: hostProfileId,
          remotePath: remotePath,
          localPath: outputFile.path,
          fileSize: totalBytes,
          remoteModifiedAt: remoteModifiedAt,
          transferOffset: transferredBytes,
          state: 'downloading',
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await for (final chunk in remoteFile.read(
        length: totalBytes == null ? null : totalBytes - transferredBytes,
        offset: transferredBytes,
      )) {
        if (cancellationToken.isCancelled) {
          throw const DownloadCancelledException();
        }
        sink.add(chunk);
        transferredBytes += chunk.length;
        await _metadataStore.upsertTransferCheckpoint(
          TransferCheckpoint(
            hostProfileId: hostProfileId,
            remotePath: remotePath,
            localPath: outputFile.path,
            fileSize: totalBytes,
            remoteModifiedAt: remoteModifiedAt,
            transferOffset: transferredBytes,
            state: 'downloading',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        onProgress(transferredBytes, totalBytes, outputFile.path);
      }
      await sink.flush();
      final finalFile = await _finalizeDownload(outputFile, fileName);
      await _metadataStore.clearTransferCheckpoint(hostProfileId, remotePath);
      return FileDownloadResult(
        fileName: fileName,
        localPath: finalFile.path,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes,
      );
    } on DownloadCancelledException {
      await sink?.close();
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

  Future<File> _partDestination(Directory directory, String fileName) async {
    final destination = await _uniqueDestination(directory, '$fileName.part');
    return destination;
  }

  Future<File> _finalizeDownload(File partFile, String originalFileName) async {
    final directory = partFile.parent;
    final finalName = originalFileName.endsWith('.part')
        ? originalFileName.substring(0, originalFileName.length - 5)
        : originalFileName;
    final destination = await _uniqueDestination(directory, finalName);
    await partFile.rename(destination.path);
    return destination;
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
