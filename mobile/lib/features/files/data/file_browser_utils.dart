import 'dart:math';

import '../../../core/config/app_settings.dart';
import '../../../core/utils/path_safety.dart';

const maxImagePreviewBytes = 25 * 1024 * 1024;
const maxTextPreviewBytes = 1024 * 1024;
const defaultSearchDepthLimit = 8;
const defaultSearchResultLimit = 500;

String buildSftpProfileId(ConnectionProfile profile) {
  return '${profile.host.trim()}:${profile.port}:${profile.username.trim()}';
}

bool isImagePreviewable(String fileName) {
  return _matchesExtension(fileName, const ['jpg', 'jpeg', 'png', 'webp', 'gif']);
}

bool isTextPreviewable(String fileName) {
  return _matchesExtension(
    fileName,
    const ['txt', 'log', 'md', 'json', 'yaml', 'yml', 'conf', 'ini', 'csv'],
  );
}

bool isVideoPreviewable(String fileName) {
  return _matchesExtension(fileName, const ['mp4', 'mkv', 'webm', 'mov', 'avi']);
}

String buildSoftDeletePath({
  required String virtualRoot,
  required String sourcePath,
  required DateTime now,
}) {
  final trashRoot = normalizeVirtualPath(virtualRoot, '$virtualRoot/.tablet-trash');
  final fileName = sourcePath.split('/').last;
  final timestamp =
      '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final randomSuffix = Random(now.microsecondsSinceEpoch).nextInt(100000);
  return '$trashRoot/$timestamp-$randomSuffix-$safeName';
}

bool canMutateFiles(AppSettings settings) {
  return settings.allowSftpUpload ||
      settings.allowSftpCreateDirectory ||
      settings.allowSftpRename ||
      settings.allowSftpMove ||
      settings.allowSftpSoftDelete;
}

bool _matchesExtension(String fileName, List<String> extensions) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return false;
  }
  final ext = fileName.substring(dotIndex + 1).toLowerCase();
  return extensions.contains(ext);
}
