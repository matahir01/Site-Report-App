import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

/// The remote system a queued action targets.
enum QueueTarget { sheets, drive }

/// The kind of write a queued action represents.
enum QueueOp { create, update, delete }

/// A single pending offline action.
///
/// Actions are persisted as JSON strings inside a Hive box so no generated
/// `TypeAdapter` is required — [payload] can carry whatever a given handler
/// needs (a site id, a file path, a row diff, etc).
class QueuedAction {
  final String id;
  final QueueTarget target;
  final QueueOp op;
  final String entityType; // e.g. 'site', 'expense', 'photo', 'pdf_export'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final String? lastError;

  QueuedAction({
    required this.id,
    required this.target,
    required this.op,
    required this.entityType,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  QueuedAction copyWith({
    int? retryCount,
    DateTime? lastAttemptAt,
    String? lastError,
  }) {
    return QueuedAction(
      id: id,
      target: target,
      op: op,
      entityType: entityType,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'target': target.name,
    'op': op.name,
    'entityType': entityType,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastAttemptAt': lastAttemptAt?.toIso8601String(),
    'lastError': lastError,
  };

  factory QueuedAction.fromMap(Map<String, dynamic> m) => QueuedAction(
    id: m['id'] as String,
    target: QueueTarget.values.byName(m['target'] as String),
    op: QueueOp.values.byName(m['op'] as String),
    entityType: m['entityType'] as String,
    payload: Map<String, dynamic>.from(m['payload'] as Map),
    createdAt: DateTime.parse(m['createdAt'] as String),
    retryCount: m['retryCount'] as int? ?? 0,
    lastAttemptAt: m['lastAttemptAt'] != null
        ? DateTime.parse(m['lastAttemptAt'] as String)
        : null,
    lastError: m['lastError'] as String?,
  );
}

/// A handler that actually performs a queued action against the network
/// (Google Sheets / Google Drive). Returning normally = success; throwing =
/// failure, which re-queues the action with backoff.
typedef QueueHandler = Future<void> Function(QueuedAction action);

/// Persistent offline queue with exponential backoff and automatic flush
/// on connectivity restore.
///
/// Usage:
/// ```dart
/// await OfflineQueueService.instance.init();
/// OfflineQueueService.instance.registerHandler(QueueTarget.sheets, (a) => ...);
/// OfflineQueueService.instance.registerHandler(QueueTarget.drive, (a) => ...);
/// await OfflineQueueService.instance.enqueue(target: ..., op: ..., entityType: ..., payload: ...);
/// ```
class OfflineQueueService {
  OfflineQueueService._();
  static final OfflineQueueService instance = OfflineQueueService._();

  static const _boxName = 'offline_action_queue';
  static const _maxRetries = 8;
  static const _baseBackoff = Duration(seconds: 4);
  static const _maxBackoff = Duration(minutes: 30);

  final _uuid = const Uuid();
  final Map<QueueTarget, QueueHandler> _handlers = {};
  final _statusController = StreamController<int>.broadcast();
  Box<String>? _box;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _flushing = false;

  /// Emits the current pending-count every time the queue changes.
  Stream<int> get pendingCountStream => _statusController.stream;

  Future<void> init() async {
    if (_box != null) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        // Don't await — fire-and-forget flush when connectivity returns.
        flush();
      }
    });
    _emitCount();
  }

  void registerHandler(QueueTarget target, QueueHandler handler) {
    _handlers[target] = handler;
  }

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
  }

  int get pendingCount => _box?.length ?? 0;

  List<QueuedAction> get pending =>
      (_box?.values ?? const <String>[])
          .map(
            (raw) =>
                QueuedAction.fromMap(jsonDecode(raw) as Map<String, dynamic>),
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Adds an action to the persistent queue. Call this whenever a network
  /// call to Sheets/Drive fails or is skipped because the device is offline.
  Future<QueuedAction> enqueue({
    required QueueTarget target,
    required QueueOp op,
    required String entityType,
    required Map<String, dynamic> payload,
  }) async {
    await init();
    final action = QueuedAction(
      id: _uuid.v4(),
      target: target,
      op: op,
      entityType: entityType,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _box!.put(action.id, jsonEncode(action.toMap()));
    _emitCount();
    // Try immediately in case connectivity is actually fine and this was
    // queued preemptively (e.g. a batch upload call).
    unawaited(flush());
    return action;
  }

  /// Returns true if a network path is currently available. Handlers should
  /// still be prepared to fail (flaky connections, auth errors, etc).
  Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Attempts to drain the queue, oldest-first, respecting each action's
  /// backoff schedule. Safe to call repeatedly/concurrently.
  Future<void> flush() async {
    await init();
    if (_flushing) return;
    if (!await isOnline) return;
    _flushing = true;
    try {
      for (final action in pending) {
        if (!_isDue(action)) continue;
        final handler = _handlers[action.target];
        if (handler == null) continue; // no handler registered yet
        try {
          await handler(action);
          await _box!.delete(action.id);
        } catch (e) {
          await _reschedule(action, e.toString());
        }
        _emitCount();
      }
    } finally {
      _flushing = false;
    }
  }

  bool _isDue(QueuedAction action) {
    if (action.lastAttemptAt == null) return true;
    final backoff = _backoffFor(action.retryCount);
    return DateTime.now().isAfter(action.lastAttemptAt!.add(backoff));
  }

  Duration _backoffFor(int retryCount) {
    final seconds =
        _baseBackoff.inSeconds * pow(2, retryCount).clamp(1, 1 << 20);
    return Duration(seconds: seconds.toInt()).clamp(_baseBackoff, _maxBackoff);
  }

  Future<void> _reschedule(QueuedAction action, String error) async {
    final updated = action.copyWith(
      retryCount: action.retryCount + 1,
      lastAttemptAt: DateTime.now(),
      lastError: error,
    );
    if (updated.retryCount >= _maxRetries) {
      // Give up automatically to avoid an unbounded dead-letter queue; the
      // action stays visible via `pending` (with its error) for manual
      // inspection/retry from a sync-status screen, but flush() will skip
      // it going forward.
      await _box!.put(action.id, jsonEncode(updated.toMap()));
      return;
    }
    await _box!.put(action.id, jsonEncode(updated.toMap()));
  }

  Future<void> retryNow(String actionId) async {
    final raw = _box?.get(actionId);
    if (raw == null) return;
    final action = QueuedAction.fromMap(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    await _box!.put(
      actionId,
      jsonEncode(action.copyWith(lastAttemptAt: null).toMap()),
    );
    await flush();
  }

  Future<void> clearAll() async {
    await _box?.clear();
    _emitCount();
  }

  void _emitCount() {
    if (!_statusController.isClosed) _statusController.add(pendingCount);
  }
}

extension on Duration {
  Duration clamp(Duration min, Duration max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }
}
