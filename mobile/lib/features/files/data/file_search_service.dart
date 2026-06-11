import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/path_safety.dart';
import '../domain/models/file_browser_models.dart';
import 'file_browser_utils.dart';

final fileSearchServiceProvider = Provider<FileSearchService>((ref) {
  return const FileSearchService();
});

class FileSearchCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class FileSearchService {
  const FileSearchService();

  Future<RemoteSearchSnapshot> search({
    required SftpClient sftp,
    required String virtualRoot,
    required String startPath,
    required String query,
    required FileSearchCancellationToken cancellationToken,
    int maxDepth = defaultSearchDepthLimit,
    int maxResults = defaultSearchResultLimit,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final normalizedStart = normalizeVirtualPath(virtualRoot, startPath);
    final stopwatch = Stopwatch()..start();
    final results = <RemoteSearchResult>[];
    String? lastVisitedPath;
    var truncated = false;

    Future<void> walk(String path, int depth) async {
      if (cancellationToken.isCancelled || depth > maxDepth) {
        return;
      }
      if (results.length >= maxResults || stopwatch.elapsed > timeout) {
        truncated = true;
        return;
      }
      lastVisitedPath = path;
      final entries = await sftp.listdir(path);
      for (final item in entries) {
        final name = item.filename;
        if (name == '.' || name == '..') {
          continue;
        }
        final childPath = path == '/' ? '/$name' : '$path/$name';
        final attrs = item.attr;
        final isDirectory = attrs.isDirectory;
        final isSymlink = attrs.isSymbolicLink;

        if (name.toLowerCase().contains(query.toLowerCase())) {
          results.add(
            RemoteSearchResult(
              entryPath: childPath,
              name: name,
              isDirectory: isDirectory,
              depth: depth,
            ),
          );
          if (results.length >= maxResults) {
            truncated = true;
            return;
          }
        }

        if (!isDirectory || isSymlink) {
          continue;
        }
        if (stopwatch.elapsed > timeout) {
          truncated = true;
          return;
        }
        await walk(normalizeVirtualPath(virtualRoot, childPath), depth + 1);
        if (cancellationToken.isCancelled || truncated) {
          return;
        }
      }
    }

    await walk(normalizedStart, 0);
    return RemoteSearchSnapshot(
      results: results,
      truncated: truncated,
      cancelled: cancellationToken.isCancelled,
      lastVisitedPath: lastVisitedPath,
    );
  }
}
