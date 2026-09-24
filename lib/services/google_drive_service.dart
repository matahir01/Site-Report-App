import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import 'google_auth.dart';
import 'offline_queue_service.dart';

class GoogleDriveService {
  static Future<drive.DriveApi> _getDriveApi() async {
    final account = await GoogleAuth.signInInteractive();
    if (account == null) throw Exception('Google Sign-In required');
    return GoogleAuth.driveApiFor(account);
  }

  /// Registers this service's queue handler once at app startup so queued
  /// Drive actions (backup + batch file uploads) can be replayed by
  /// [SyncEngine.runSync] / [OfflineQueueService.flush] when connectivity
  /// returns.
  static void registerQueueHandler() {
    OfflineQueueService.instance.registerHandler(QueueTarget.drive, (
      action,
    ) async {
      switch (action.entityType) {
        case 'backup':
          await uploadBackup();
          break;
        case 'file':
          final path = action.payload['localPath'] as String;
          final folder = action.payload['folder'] as String? ?? 'appDataFolder';
          await _uploadFileNow(File(path), folderRef: folder);
          break;
        default:
          throw Exception(
            'Unknown drive queue entityType: ${action.entityType}',
          );
      }
    });
  }

  static Future<drive.File> uploadBackup() async {
    final api = await _getDriveApi();
    final dbPath = await DatabaseHelper.instance.getDbPath();
    final file = File(dbPath);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final media = drive.Media(file.openRead(), file.lengthSync());
    final driveFile = drive.File()
      ..name = 'site_daily_log_backup_$timestamp.db'
      ..parents = ['appDataFolder'];
    return api.files.create(driveFile, uploadMedia: media);
  }

  /// Backup, but network-safe: if offline or the upload throws, the backup
  /// is queued instead of failing outright. Call this from UI code instead
  /// of [uploadBackup] directly.
  static Future<bool> backupNowOrQueue() async {
    if (!await OfflineQueueService.instance.isOnline) {
      await OfflineQueueService.instance.enqueue(
        target: QueueTarget.drive,
        op: QueueOp.create,
        entityType: 'backup',
        payload: const {},
      );
      return false;
    }
    try {
      await uploadBackup();
      return true;
    } catch (e) {
      await OfflineQueueService.instance.enqueue(
        target: QueueTarget.drive,
        op: QueueOp.create,
        entityType: 'backup',
        payload: const {},
      );
      return false;
    }
  }

  static Future<drive.File> _uploadFileNow(
    File file, {
    required String folderRef,
  }) async {
    final api = await _getDriveApi();
    final media = drive.Media(file.openRead(), file.lengthSync());
    final driveFile = drive.File()
      ..name = p.basename(file.path)
      ..parents = [folderRef];
    return api.files.create(driveFile, uploadMedia: media);
  }

  /// Uploads a single file now, or queues it for later if offline/failed.
  /// Use for one-off uploads (e.g. sharing a single PDF report).
  static Future<bool> uploadFileOrQueue(
    File file, {
    String folderRef = 'appDataFolder',
  }) async {
    if (await OfflineQueueService.instance.isOnline) {
      try {
        await _uploadFileNow(file, folderRef: folderRef);
        return true;
      } catch (_) {
        // fall through to queue
      }
    }
    await OfflineQueueService.instance.enqueue(
      target: QueueTarget.drive,
      op: QueueOp.create,
      entityType: 'file',
      payload: {'localPath': file.path, 'folder': folderRef},
    );
    return false;
  }

  /// Batch capability requested by Phase 3: queue every photo watermark /
  /// offline PDF export produced while offline in one call, then let
  /// [SyncEngine.runSync] drain them (respecting backoff) once the device
  /// is back online, instead of the caller uploading one-by-one.
  static Future<void> queueBatchUpload(
    List<String> localPaths, {
    String folderRef = 'appDataFolder',
  }) async {
    for (final path in localPaths) {
      await OfflineQueueService.instance.enqueue(
        target: QueueTarget.drive,
        op: QueueOp.create,
        entityType: 'file',
        payload: {'localPath': path, 'folder': folderRef},
      );
    }
  }

  static Future<List<drive.File>> listBackups() async {
    final api = await _getDriveApi();
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains 'site_daily_log_backup'",
      orderBy: 'createdTime desc',
    );
    return result.files ?? [];
  }

  static Future<void> restoreFromBackup(drive.File backup) async {
    final api = await _getDriveApi();
    final media = await api.files.get(
      backup.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.fold<List<int>>(
      [],
      (prev, chunk) => prev..addAll(chunk),
    );
    final dbPath = await DatabaseHelper.instance.getDbPath();
    await DatabaseHelper.instance.closeForRestore();
    final file = File(dbPath);
    await file.writeAsBytes(bytes, flush: true);
  }
}

/// Legacy simple pending-count badge, kept for existing call sites.
/// New code should prefer [SyncEngine] for full status (idle/syncing/
/// success/conflict/offline/error) — this now just mirrors the queue size
/// on top of any local (non-Sheets/Drive) pending-sync rows already
/// tracked by [DatabaseHelper].
class SyncStatusProvider extends ChangeNotifier {
  int _pendingCount = 0;

  int get pendingCount => _pendingCount;

  Future<void> refresh() async {
    final localPending = await DatabaseHelper.instance.getPendingSyncCount();
    final queuePending = OfflineQueueService.instance.pendingCount;
    _pendingCount = localPending + queuePending;
    notifyListeners();
  }
}
