import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/site.dart';
import '../models/expense.dart';
import '../models/cash_float.dart';
import 'google_auth.dart';
import 'offline_queue_service.dart';

/// Current sync state for a site's linked Google Sheet, read from the
/// local `sheet_sync` table.
class SheetSyncStatus {
  final String? spreadsheetId;
  final String? spreadsheetUrl;
  final bool autoSync;
  final DateTime? lastSyncedAt;
  final String? lastSyncError;

  SheetSyncStatus({
    this.spreadsheetId,
    this.spreadsheetUrl,
    this.autoSync = false,
    this.lastSyncedAt,
    this.lastSyncError,
  });

  bool get isLinked => spreadsheetId != null;

  factory SheetSyncStatus.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SheetSyncStatus();
    return SheetSyncStatus(
      spreadsheetId: map['spreadsheet_id'] as String?,
      spreadsheetUrl: map['spreadsheet_url'] as String?,
      autoSync: (map['auto_sync'] as int?) == 1,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.tryParse(map['last_synced_at'] as String)
          : null,
      lastSyncError: map['last_sync_error'] as String?,
    );
  }
}

/// One-way push sync: the local SQLite database is always the source of
/// truth. Each sync fully refreshes a fixed set of tabs in the linked
/// Google Sheet to mirror current data — it never reads changes back from
/// the Sheet.
class GoogleSheetsService {
  static const _tabs = [
    'Daily Logs',
    'Expenses',
    'Material Stock',
    'Equipment Dip',
    'Diesel Activity',
    'Cash Flow',
  ];

  static Future<SheetSyncStatus> getStatus(String siteId) async {
    final row = await DatabaseHelper.instance.getSheetSync(siteId);
    return SheetSyncStatus.fromMap(row);
  }

  static Future<void> setAutoSync(String siteId, bool enabled) async {
    await DatabaseHelper.instance.upsertSheetSync(
      siteId: siteId,
      autoSync: enabled,
    );
  }

  /// Explicit, user-initiated action: signs in interactively if needed,
  /// creates the spreadsheet on first use, and pushes current data.
  /// Returns the spreadsheet's shareable URL.
  static Future<String> connectAndSync(Site site) async {
    final account = await GoogleAuth.signInInteractive();
    if (account == null) throw Exception('Google Sign-In required');
    final api = await GoogleAuth.sheetsApiFor(account);

    var status = await getStatus(site.id);
    var spreadsheetId = status.spreadsheetId;
    String? url = status.spreadsheetUrl;

    if (spreadsheetId == null) {
      final created = await api.spreadsheets.create(
        sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(
            title: 'Site Daily Log — ${site.name}',
          ),
          sheets: [
            for (final name in _tabs)
              sheets.Sheet(properties: sheets.SheetProperties(title: name)),
          ],
        ),
      );
      spreadsheetId = created.spreadsheetId;
      url = created.spreadsheetUrl;
    } else {
      await _ensureTabsExist(api, spreadsheetId);
    }

    await _pushAllData(api, spreadsheetId!, site);

    final now = DateTime.now().toIso8601String();
    await DatabaseHelper.instance.upsertSheetSync(
      siteId: site.id,
      spreadsheetId: spreadsheetId,
      spreadsheetUrl: url,
      autoSync: true,
      lastSyncedAt: now,
      lastSyncError: null,
    );
    return url!;
  }

  static Future<void> disconnect(String siteId) async {
    await DatabaseHelper.instance.upsertSheetSync(
      siteId: siteId,
      spreadsheetId: null,
      spreadsheetUrl: null,
      autoSync: false,
    );
  }

  /// Registers this service's queue handler once at app startup so a
  /// silent auto-sync push that failed offline gets replayed by
  /// [SyncEngine.runSync] once connectivity returns, instead of being lost.
  static void registerQueueHandler() {
    OfflineQueueService.instance.registerHandler(QueueTarget.sheets, (
      action,
    ) async {
      final siteId = action.payload['siteId'] as String;
      await _pushNow(siteId);
    });
  }

  /// Silent, background push used right after a save completes elsewhere
  /// in the app. Never shows a sign-in prompt — if there's no existing
  /// Google session, or the site isn't linked/auto-sync isn't on, this
  /// quietly does nothing. If the device is offline (or the push fails),
  /// the push is queued instead of just recording an error string, so it
  /// replays automatically once connectivity returns.
  static Future<void> autoSyncSite(String siteId) async {
    final status = await getStatus(siteId);
    if (!status.autoSync || status.spreadsheetId == null) return;

    if (!await OfflineQueueService.instance.isOnline) {
      await OfflineQueueService.instance.enqueue(
        target: QueueTarget.sheets,
        op: QueueOp.update,
        entityType: 'site_push',
        payload: {'siteId': siteId},
      );
      await DatabaseHelper.instance.upsertSheetSync(
        siteId: siteId,
        lastSyncError: 'Offline — queued for sync when connection returns.',
      );
      return;
    }

    try {
      await _pushNow(siteId);
    } catch (e) {
      await OfflineQueueService.instance.enqueue(
        target: QueueTarget.sheets,
        op: QueueOp.update,
        entityType: 'site_push',
        payload: {'siteId': siteId},
      );
      await DatabaseHelper.instance.upsertSheetSync(
        siteId: siteId,
        lastSyncError: e.toString(),
      );
    }
  }

  /// Shared push implementation used by both the direct path and the
  /// queued-replay path, so retries hit exactly the same logic.
  static Future<void> _pushNow(String siteId) async {
    final status = await getStatus(siteId);
    if (status.spreadsheetId == null) return;
    final account = await GoogleAuth.signInSilentlyOnly();
    if (account == null) {
      throw Exception(
        'Not signed in to Google — open Sheets Sync to reconnect.',
      );
    }
    final api = await GoogleAuth.sheetsApiFor(account);
    final site = await DatabaseHelper.instance.getSiteById(siteId);
    if (site == null) return;

    await _pushAllData(api, status.spreadsheetId!, site);

    await DatabaseHelper.instance.upsertSheetSync(
      siteId: siteId,
      lastSyncedAt: DateTime.now().toIso8601String(),
      lastSyncError: null,
    );
  }

  static Future<void> _ensureTabsExist(
    sheets.SheetsApi api,
    String spreadsheetId,
  ) async {
    final spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final existing = (spreadsheet.sheets ?? [])
        .map((s) => s.properties?.title)
        .whereType<String>()
        .toSet();
    final missing = _tabs.where((t) => !existing.contains(t)).toList();
    if (missing.isEmpty) return;
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          for (final name in missing)
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: name),
              ),
            ),
        ],
      ),
      spreadsheetId,
    );
  }

  static Future<void> _pushAllData(
    sheets.SheetsApi api,
    String spreadsheetId,
    Site site,
  ) async {
    final db = DatabaseHelper.instance;
    final dateFmt = DateFormat.yMMMd();

    final logs = await db.getLogsForSite(site.id);
    final expenses = await db.getExpensesForSite(site.id);
    final materialRows = await db.getMaterialStockLogsForSite(site.id);
    final equipmentRows = await db.getEquipmentDippingLogsForSite(site.id);
    final dieselRows = await db.getDieselActivityForSite(site.id);
    final cashFloats = await db.getCashFloatsForSite(site.id);

    await _writeTab(api, spreadsheetId, 'Daily Logs', [
      ['Date', 'Weather', 'Crew Count', 'Work Completed', 'Issues / Delays'],
      for (final l in logs)
        [
          dateFmt.format(l.date),
          l.weather ?? '',
          l.crewCount?.toString() ?? '',
          l.workCompleted ?? '',
          l.issues ?? '',
        ],
    ]);

    await _writeTab(api, spreadsheetId, 'Expenses', [
      [
        'Date',
        'Category',
        'S/N',
        'Description',
        'Unit',
        'Unit Price',
        'Amount',
      ],
      for (final Expense e in expenses)
        [
          dateFmt.format(e.date),
          e.category.label,
          e.serialNo?.toString() ?? '',
          e.displayDescription,
          e.unit ?? '',
          (e.unitPrice ?? e.amount).toStringAsFixed(2),
          e.amount.toStringAsFixed(2),
        ],
    ]);

    await _writeTab(api, spreadsheetId, 'Material Stock', [
      ['Date', 'Item', 'Unit', 'Opening', 'Received', 'Issued', 'Closing'],
      for (final r in materialRows)
        [
          _fmtDate(r['log_date']),
          r['item_name']?.toString() ?? '',
          r['unit']?.toString() ?? '',
          _fmtNum(r['opening_balance']),
          _fmtNum(r['received']),
          _fmtNum(r['issued']),
          _fmtNum(r['closing_balance']),
        ],
    ]);

    await _writeTab(api, spreadsheetId, 'Equipment Dip', [
      [
        'Date',
        'Equipment',
        'Open Dip (cm)',
        'Close Dip (cm)',
        'Diesel (L)',
        'Engine Oil (L)',
      ],
      for (final r in equipmentRows)
        [
          _fmtDate(r['log_date']),
          r['equipment_name']?.toString() ?? '',
          _fmtNum(r['opening_dip_cm']),
          _fmtNum(r['closing_dip_cm']),
          _fmtNum(r['diesel_issued_litres']),
          _fmtNum(r['engine_oil_issued_litres']),
        ],
    ]);

    await _writeTab(api, spreadsheetId, 'Diesel Activity', [
      ['Date', 'Activity / Machine', 'Litres Issued'],
      for (final r in dieselRows)
        [
          _fmtDate(r['log_date']),
          r['activity_name']?.toString() ?? '',
          _fmtNum(r['litres_issued']),
        ],
    ]);

    await _writeTab(api, spreadsheetId, 'Cash Flow', [
      [
        'Date',
        'Opening',
        'Float Received',
        'Total Expenses',
        'Expected Close',
        'Reported Close',
        'Variance',
        'Status',
      ],
      for (final c in cashFloats)
        [
          dateFmt.format(c.date),
          c.openingBalance.toStringAsFixed(2),
          c.floatReceived.toStringAsFixed(2),
          c.totalExpenses.toStringAsFixed(2),
          c.expectedClosingBalance.toStringAsFixed(2),
          c.reportedClosingBalance.toStringAsFixed(2),
          c.variance.toStringAsFixed(2),
          c.status.label,
        ],
    ]);
  }

  static String _fmtDate(dynamic isoDate) {
    if (isoDate == null) return '';
    final d = DateTime.tryParse(isoDate.toString());
    return d != null ? DateFormat.yMMMd().format(d) : isoDate.toString();
  }

  static String _fmtNum(dynamic v) {
    if (v == null) return '';
    final n = v is num ? v : num.tryParse(v.toString());
    return n?.toStringAsFixed(1) ?? '';
  }

  static Future<void> _writeTab(
    sheets.SheetsApi api,
    String spreadsheetId,
    String tabName,
    List<List<Object?>> rows,
  ) async {
    // Full refresh: clear whatever was there before writing the current
    // snapshot, so deleted/edited records don't linger as stale rows.
    await api.spreadsheets.values.clear(
      sheets.ClearValuesRequest(),
      spreadsheetId,
      "'$tabName'",
    );
    if (rows.isEmpty) return;
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: rows),
      spreadsheetId,
      "'$tabName'!A1",
      valueInputOption: 'RAW',
    );
  }
}
