import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'file_browser_utils.dart';

final filePreviewServiceProvider = Provider<FilePreviewService>((ref) {
  return const FilePreviewService();
});

class FilePreviewService {
  const FilePreviewService();

  Future<String> readTextPreview({
    required SftpClient sftp,
    required String remotePath,
    required int sizeBytes,
  }) async {
    if (sizeBytes > maxTextPreviewBytes) {
      throw const FilePreviewException(
        'Text preview exceeds the 512 KB limit.',
      );
    }
    final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in remoteFile.read(length: sizeBytes)) {
        buffer.add(chunk);
      }
      return utf8.decode(buffer.takeBytes(), allowMalformed: true);
    } finally {
      await remoteFile.close();
    }
  }

  Future<String> cacheRemoteFile({
    required SftpClient sftp,
    required String remotePath,
    required String fileName,
    required int? sizeBytes,
  }) async {
    if (sizeBytes != null &&
        sizeBytes > maxImagePreviewBytes &&
        !isVideoPreviewable(fileName)) {
      throw const FilePreviewException('Preview exceeds the 25 MB limit.');
    }
    final cacheDir = await _ensureCacheDirectory();
    final output = File('${cacheDir.path}/${_sanitize(fileName)}');
    final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    final sink = output.openWrite();
    try {
      await for (final chunk in remoteFile.read(length: sizeBytes)) {
        sink.add(chunk);
      }
      await sink.flush();
      return output.path;
    } finally {
      await sink.close();
      await remoteFile.close();
    }
  }

  Future<Directory> _ensureCacheDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docs.path}/previews');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _sanitize(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}

class FilePreviewException implements Exception {
  const FilePreviewException(this.message);

  final String message;

  @override
  String toString() => message;
}
