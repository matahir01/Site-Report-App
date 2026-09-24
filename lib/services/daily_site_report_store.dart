import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/daily_site_report_meta.dart';

/// Stores report-only fields that should not duplicate the core daily-log,
/// material, attendance, equipment, concrete, or expense records.
///
/// The table is created lazily with CREATE TABLE IF NOT EXISTS so existing
/// installations gain the new report metadata safely without destructive
/// database changes.
class DailySiteReportStore {
  DailySiteReportStore._();
  static final DailySiteReportStore instance = DailySiteReportStore._();

  bool _schemaReady = false;

  Future<Database> _database() async {
    final db = await DatabaseHelper.instance.database;
    if (!_schemaReady) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_site_report_meta (
          daily_log_id TEXT PRIMARY KEY,
          report_no TEXT,
          shift TEXT,
          progress_quantity TEXT,
          progress_unit TEXT,
          percent_complete REAL,
          quality_inspections TEXT,
          hse_observations TEXT,
          site_instructions TEXT,
          next_day_plan TEXT,
          document_references TEXT,
          prepared_by TEXT,
          prepared_by_position TEXT,
          reviewed_by TEXT,
          approved_by TEXT,
          prepared_signature_path TEXT,
          reviewed_signature_path TEXT,
          approved_signature_path TEXT,
          FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
        )
      ''');
      _schemaReady = true;
    }
    return db;
  }

  Future<void> upsert(DailySiteReportMeta meta) async {
    final db = await _database();
    await db.insert(
      'daily_site_report_meta',
      meta.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DailySiteReportMeta?> getForLog(String dailyLogId) async {
    final db = await _database();
    final rows = await db.query(
      'daily_site_report_meta',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailySiteReportMeta.fromMap(rows.first);
  }

  Future<void> deleteForLog(String dailyLogId) async {
    final db = await _database();
    await db.delete(
      'daily_site_report_meta',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
  }
}
