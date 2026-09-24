import 'dart:async';

import 'package:flutter/foundation.dart';

import 'offline_queue_service.dart';

/// High-level sync state surfaced to the UI (badges, sync screen, snackbars).
enum SyncStatus { idle, syncing, success, conflict, offline, error }

/// Which side won a last-write-wins conflict resolution.
enum ConflictWinner { local, remote, tie }

/// Result of resolving a single field/record conflict.
class ConflictResolution {
  final ConflictWinner winner;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;

  const ConflictResolution({
    required this.winner,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
  });
}

/// Orchestrates the offline queue, reports a single [SyncStatus] the whole
/// app can bind to (via `Provider`/`Consumer`), and resolves two-way sync
/// conflicts with a last-write-wins strategy driven by `updatedAt`
/// timestamps already present on every model.
///
/// This does not talk to Sheets/Drive directly — [OfflineQueueService]
/// handlers do that. SyncEngine's job is orchestration + status + conflicts.
class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncAt;
  String? _lastError;
  int _conflictsResolvedThisRun = 0;
  StreamSubscription<int>? _queueSub;

  SyncStatus get status => _status;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;
  int get pendingCount => OfflineQueueService.instance.pendingCount;
  int get conflictsResolvedThisRun => _conflictsResolvedThisRun;

  Future<void> init() async {
    await OfflineQueueService.instance.init();
    _queueSub ??= OfflineQueueService.instance.pendingCountStream.listen((_) {
      notifyListeners();
    });
  }

  void _setStatus(SyncStatus s, {String? error}) {
    _status = s;
    _lastError = error;
    notifyListeners();
  }

  /// Resolves a conflict between a local and remote record using
  /// last-write-wins on `updatedAt`. Ties (identical timestamp) favor the
  /// remote copy, since the server is the point of truth for other devices.
  ConflictResolution resolveLastWriteWins({
    required DateTime localUpdatedAt,
    required DateTime remoteUpdatedAt,
  }) {
    final ConflictWinner winner;
    if (localUpdatedAt.isAtSameMomentAs(remoteUpdatedAt)) {
      winner = ConflictWinner.tie;
    } else if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
      winner = ConflictWinner.local;
    } else {
      winner = ConflictWinner.remote;
    }
    _conflictsResolvedThisRun++;
    return ConflictResolution(
      winner: winner,
      localUpdatedAt: localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt,
    );
  }

  /// Runs a full sync pass: checks connectivity, drains the offline queue,
  /// and reports status throughout. Safe to call from a pull-to-refresh,
  /// a periodic timer, or a "Sync now" button.
  Future<void> runSync() async {
    await init();
    _conflictsResolvedThisRun = 0;

    if (!await OfflineQueueService.instance.isOnline) {
      _setStatus(SyncStatus.offline);
      return;
    }

    _setStatus(SyncStatus.syncing);
    try {
      await OfflineQueueService.instance.flush();
      final stillPending = OfflineQueueService.instance.pendingCount;
      _lastSyncAt = DateTime.now();
      if (stillPending > 0) {
        // Some actions hit their retry ceiling or a handler wasn't ready —
        // surface as a soft conflict/attention state rather than a hard
        // error so the UI can prompt a manual retry.
        _setStatus(SyncStatus.conflict);
      } else {
        _setStatus(SyncStatus.success);
      }
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    }
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    super.dispose();
  }
}
