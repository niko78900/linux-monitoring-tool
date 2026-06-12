import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models/file_browser_models.dart';

final fileMetadataStoreProvider = Provider<FileMetadataStore>((ref) {
  return const FileMetadataStore();
});

class FileMetadataStore {
  const FileMetadataStore();

  Future<Database> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = '${docs.path}/file-browser.sqlite3';
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE favorite_paths('
          'host_profile_id TEXT NOT NULL,'
          'remote_path TEXT NOT NULL,'
          'created_at INTEGER NOT NULL,'
          'PRIMARY KEY(host_profile_id, remote_path)'
          ')',
        );
        await db.execute(
          'CREATE TABLE recent_downloads('
          'host_profile_id TEXT NOT NULL,'
          'remote_path TEXT NOT NULL,'
          'file_name TEXT NOT NULL,'
          'local_path TEXT NOT NULL,'
          'size_bytes INTEGER,'
          'remote_modified_at INTEGER,'
          'downloaded_at INTEGER NOT NULL,'
          'PRIMARY KEY(host_profile_id, remote_path)'
          ')',
        );
        await db.execute(
          'CREATE TABLE transfer_jobs('
          'host_profile_id TEXT NOT NULL,'
          'remote_path TEXT NOT NULL,'
          'local_path TEXT NOT NULL,'
          'file_size INTEGER,'
          'remote_modified_at INTEGER,'
          'transfer_offset INTEGER NOT NULL,'
          'state TEXT NOT NULL,'
          'updated_at INTEGER NOT NULL,'
          'PRIMARY KEY(host_profile_id, remote_path)'
          ')',
        );
        await db.execute(
          'CREATE TABLE file_browser_preferences('
          'host_profile_id TEXT NOT NULL,'
          'pref_key TEXT NOT NULL,'
          'pref_value TEXT NOT NULL,'
          'updated_at INTEGER NOT NULL,'
          'PRIMARY KEY(host_profile_id, pref_key)'
          ')',
        );
      },
    );
  }

  Future<List<FavoriteLocation>> listFavorites(String hostProfileId) async {
    final db = await open();
    final rows = await db.query(
      'favorite_paths',
      where: 'host_profile_id = ?',
      whereArgs: [hostProfileId],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => FavoriteLocation(
            hostProfileId: row['host_profile_id'] as String,
            remotePath: row['remote_path'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
              isUtc: true,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> addFavorite(String hostProfileId, String remotePath) async {
    final db = await open();
    await db.insert('favorite_paths', {
      'host_profile_id': hostProfileId,
      'remote_path': remotePath,
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFavorite(String hostProfileId, String remotePath) async {
    final db = await open();
    await db.delete(
      'favorite_paths',
      where: 'host_profile_id = ? AND remote_path = ?',
      whereArgs: [hostProfileId, remotePath],
    );
  }

  Future<List<RecentDownloadRecord>> listRecentDownloads(
    String hostProfileId,
  ) async {
    final db = await open();
    final rows = await db.query(
      'recent_downloads',
      where: 'host_profile_id = ?',
      whereArgs: [hostProfileId],
      orderBy: 'downloaded_at DESC',
      limit: 20,
    );
    return rows
        .map(
          (row) => RecentDownloadRecord(
            hostProfileId: row['host_profile_id'] as String,
            fileName: row['file_name'] as String,
            remotePath: row['remote_path'] as String,
            localPath: row['local_path'] as String,
            sizeBytes: row['size_bytes'] as int?,
            remoteModifiedAt: _readEpoch(row['remote_modified_at']),
            downloadedAt:
                _readEpoch(row['downloaded_at']) ?? DateTime.now().toUtc(),
          ),
        )
        .toList(growable: false);
  }

  Future<void> upsertRecentDownload(RecentDownloadRecord record) async {
    final db = await open();
    await db.insert('recent_downloads', {
      'host_profile_id': record.hostProfileId,
      'remote_path': record.remotePath,
      'file_name': record.fileName,
      'local_path': record.localPath,
      'size_bytes': record.sizeBytes,
      'remote_modified_at': record.remoteModifiedAt?.millisecondsSinceEpoch,
      'downloaded_at': record.downloadedAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeRecentDownload(
    String hostProfileId,
    String remotePath,
  ) async {
    final db = await open();
    await db.delete(
      'recent_downloads',
      where: 'host_profile_id = ? AND remote_path = ?',
      whereArgs: [hostProfileId, remotePath],
    );
  }

  Future<TransferCheckpoint?> readTransferCheckpoint(
    String hostProfileId,
    String remotePath,
  ) async {
    final db = await open();
    final rows = await db.query(
      'transfer_jobs',
      where: 'host_profile_id = ? AND remote_path = ?',
      whereArgs: [hostProfileId, remotePath],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return TransferCheckpoint(
      hostProfileId: row['host_profile_id'] as String,
      remotePath: row['remote_path'] as String,
      localPath: row['local_path'] as String,
      fileSize: row['file_size'] as int?,
      remoteModifiedAt: _readEpoch(row['remote_modified_at']),
      transferOffset: row['transfer_offset'] as int? ?? 0,
      state: row['state'] as String? ?? 'unknown',
      updatedAt: _readEpoch(row['updated_at']) ?? DateTime.now().toUtc(),
    );
  }

  Future<void> upsertTransferCheckpoint(TransferCheckpoint checkpoint) async {
    final db = await open();
    await db.insert('transfer_jobs', {
      'host_profile_id': checkpoint.hostProfileId,
      'remote_path': checkpoint.remotePath,
      'local_path': checkpoint.localPath,
      'file_size': checkpoint.fileSize,
      'remote_modified_at': checkpoint.remoteModifiedAt?.millisecondsSinceEpoch,
      'transfer_offset': checkpoint.transferOffset,
      'state': checkpoint.state,
      'updated_at': checkpoint.updatedAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearTransferCheckpoint(
    String hostProfileId,
    String remotePath,
  ) async {
    final db = await open();
    await db.delete(
      'transfer_jobs',
      where: 'host_profile_id = ? AND remote_path = ?',
      whereArgs: [hostProfileId, remotePath],
    );
  }

  DateTime? _readEpoch(Object? value) {
    final millis = value as int?;
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
}
