import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final historyCacheServiceProvider = Provider<HistoryCacheService>(
  (ref) => HistoryCacheService(
    readRootDirectory: getApplicationDocumentsDirectory,
  ),
);

class HistoryCacheService {
  HistoryCacheService({
    required Future<Directory> Function() readRootDirectory,
  }) : _readRootDirectory = readRootDirectory;

  final Future<Directory> Function() _readRootDirectory;

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final file = await _fileForKey(key);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  Future<CachedJsonPayload?> read(String key) async {
    final file = await _fileForKey(key);
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final payload = decoded['payload'];
    if (payload is! Map) {
      return null;
    }
    return CachedJsonPayload(
      cachedAt: DateTime.tryParse(decoded['cached_at'] as String? ?? ''),
      payload: payload.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }

  Future<File> _fileForKey(String key) async {
    final root = await _readRootDirectory();
    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return File('${root.path}${Platform.pathSeparator}history-cache${Platform.pathSeparator}$safeKey.json');
  }
}

class CachedJsonPayload {
  const CachedJsonPayload({
    required this.cachedAt,
    required this.payload,
  });

  final DateTime? cachedAt;
  final Map<String, dynamic> payload;
}
