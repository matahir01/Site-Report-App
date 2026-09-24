import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../models/worker.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/cash_float.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/concrete_pour.dart';

class DatabaseHelper {
  DatabaseHelper._internal({
    DatabaseFactory? factoryOverride,
    String? databasePathOverride,
  }) : _factoryOverride = factoryOverride,
       _databasePathOverride = databasePathOverride;

  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// Creates an isolated database instance for migration and repository tests.
  /// Production code must use [instance].
  factory DatabaseHelper.forTesting({
    required DatabaseFactory factory,
    required String path,
  }) => DatabaseHelper._internal(
    factoryOverride: factory,
    databasePathOverride: path,
  );

  final DatabaseFactory? _factoryOverride;
  final String? _databasePathOverride;
  Database? _db;

  static const int _dbVersion = 7;

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<String> getDbPath() async {
    if (_databasePathOverride != null) return _databasePathOverride!;
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'site_daily_log.db');
  }

  Future<void> closeForRestore() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDb() async {
    final path = await getDbPath();
    final factory = _factoryOverride ?? databaseFactory;
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        client TEXT,
        project_name TEXT NOT NULL,
        client_name TEXT,
        site_location TEXT,
        gps_coordinates TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sites (
        id TEXT PRIMARY KEY,
        projectId TEXT NOT NULL,
        name TEXT NOT NULL,
        address TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_logs (
        id TEXT PRIMARY KEY,
        siteId TEXT NOT NULL,
        date TEXT NOT NULL,
        weather TEXT,
        crewCount INTEGER,
        workCompleted TEXT,
        issues TEXT,
        photoPaths TEXT,
        lat REAL,
        lng REAL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (siteId) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        siteId TEXT NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        category_id INTEGER,
        amount REAL NOT NULL,
        note TEXT,
        receiptPhotoPath TEXT,
        serial_no INTEGER,
        description TEXT,
        unit TEXT NOT NULL DEFAULT '1',
        quantity REAL NOT NULL DEFAULT 1.0,
        unit_price REAL,
        total_amount REAL,
        daily_float_id TEXT,
        month TEXT,
        FOREIGN KEY (siteId) REFERENCES sites (id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES categories (id),
        FOREIGN KEY (daily_float_id) REFERENCES cash_floats (id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE materials_and_equipment (
        id TEXT PRIMARY KEY,
        log_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT,
        category TEXT NOT NULL DEFAULT 'material',
        FOREIGN KEY (log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    await _createV3Tables(db);
    await _createV4Tables(db);
    await _createV5Tables(db);
    await _createV6Tables(db);
    await _createV7Tables(db, isUpgrade: false);
  }

  Future<void> _createV6Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS concrete_pours (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        element_name TEXT NOT NULL,
        concrete_grade TEXT NOT NULL,
        volume_m3 REAL NOT NULL DEFAULT 0.0,
        slump_mm REAL,
        cubes_cast INTEGER NOT NULL DEFAULT 0,
        batch_ticket_no TEXT,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    // Engine-hour meter readings for machinery burn-rate calculations.
    // equipment_dipping_logs is created by _createV3Tables (above) without
    // these columns, so this ALTER is needed on both a fresh install and an
    // upgrade from an older version. try/catch guards against ever running
    // it twice against the same database.
    for (final col in [
      'opening_engine_hours REAL',
      'closing_engine_hours REAL',
    ]) {
      try {
        await db.execute('ALTER TABLE equipment_dipping_logs ADD COLUMN $col');
      } catch (_) {}
    }
  }

  Future<void> _createV5Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sheet_sync (
        site_id TEXT PRIMARY KEY,
        spreadsheet_id TEXT,
        spreadsheet_url TEXT,
        auto_sync INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        last_sync_error TEXT,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS diesel_activity_issuance (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        activity_name TEXT NOT NULL,
        litres_issued REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workers (
        id TEXT PRIMARY KEY,
        site_id TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_attendance (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        worker_id TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE,
        FOREIGN KEY (worker_id) REFERENCES workers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS material_stock_logs (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        received REAL NOT NULL DEFAULT 0.0,
        issued REAL NOT NULL DEFAULT 0.0,
        closing_balance REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS equipment_dipping_logs (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        equipment_name TEXT NOT NULL,
        opening_dip_cm REAL,
        closing_dip_cm REAL,
        diesel_issued_litres REAL NOT NULL DEFAULT 0.0,
        engine_oil_issued_litres REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_floats (
        id TEXT PRIMARY KEY,
        site_id TEXT NOT NULL,
        date TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        float_received REAL NOT NULL DEFAULT 0.0,
        total_expenses REAL NOT NULL DEFAULT 0.0,
        expected_closing_balance REAL NOT NULL DEFAULT 0.0,
        reported_closing_balance REAL NOT NULL DEFAULT 0.0,
        variance REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'OK',
        notes TEXT,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE,
        UNIQUE(site_id, entry_date)
      )
    ''');
  }

  Future<void> _createV7Tables(Database db, {required bool isUpgrade}) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL UNIQUE
      )
    ''');
    final batch = db.batch();
    for (var i = 0; i < ExpenseCategory.values.length; i++) {
      batch.insert('categories', {
        'id': i + 1,
        'name': ExpenseCategory.values[i].label,
        'sort_order': i + 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);

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

    if (isUpgrade) {
      for (final statement in [
        'ALTER TABLE projects ADD COLUMN project_name TEXT',
        'ALTER TABLE projects ADD COLUMN client_name TEXT',
        'ALTER TABLE projects ADD COLUMN site_location TEXT',
        'ALTER TABLE projects ADD COLUMN gps_coordinates TEXT',
        'ALTER TABLE expenses ADD COLUMN category_id INTEGER',
        'ALTER TABLE expenses ADD COLUMN quantity REAL NOT NULL DEFAULT 1.0',
        'ALTER TABLE expenses ADD COLUMN daily_float_id TEXT',
        'ALTER TABLE cash_floats ADD COLUMN entry_date TEXT',
        'ALTER TABLE daily_site_report_meta ADD COLUMN prepared_signature_path TEXT',
        'ALTER TABLE daily_site_report_meta ADD COLUMN reviewed_signature_path TEXT',
        'ALTER TABLE daily_site_report_meta ADD COLUMN approved_signature_path TEXT',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {
          // A lazily-created table or partially upgraded database may already
          // contain this column. Every statement is intentionally idempotent.
        }
      }
      await db.execute('''
        UPDATE projects SET
          project_name = COALESCE(project_name, name),
          client_name = COALESCE(client_name, client)
      ''');
      await db.execute('''
        UPDATE expenses SET
          quantity = CASE
            WHEN COALESCE(unit_price, 0) > 0
              THEN MAX(1.0, COALESCE(total_amount, amount) / unit_price)
            ELSE 1.0
          END,
          category_id = CASE category
            WHEN 'fuelAndLubricants' THEN 1
            WHEN 'materials' THEN 2
            WHEN 'wagesAllowancesAdvances' THEN 3
            WHEN 'transport' THEN 4
            WHEN 'repairsAndMaintenance' THEN 5
            WHEN 'toolsAndEquipment' THEN 6
            WHEN 'medicalExpenses' THEN 7
            WHEN 'labour' THEN 8
            WHEN 'siteWelfareAndSafety' THEN 9
            ELSE 10
          END
      ''');
      await db.execute('''
        UPDATE expenses
        SET unit = '1'
        WHERE unit IS NULL OR TRIM(unit) = ''
      ''');
      await db.execute('''
        UPDATE cash_floats
        SET entry_date = COALESCE(entry_date, substr(date, 1, 10))
      ''');
      await db.execute('''
        DELETE FROM cash_floats
        WHERE rowid NOT IN (
          SELECT MAX(rowid) FROM cash_floats GROUP BY site_id, entry_date
        )
      ''');
    }

    await db.execute('''
      UPDATE expenses SET daily_float_id = (
        SELECT c.id FROM cash_floats c
        WHERE c.site_id = expenses.siteId
          AND c.entry_date = substr(expenses.date, 1, 10)
        LIMIT 1
      )
      WHERE daily_float_id IS NULL
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_floats_site_entry_date
      ON cash_floats(site_id, entry_date)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_expenses_site_date
      ON expenses(siteId, date)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_expenses_category_month
      ON expenses(category_id, month)
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS expenses_recalculate_after_insert
      AFTER INSERT ON expenses
      BEGIN
        UPDATE expenses SET
          quantity = COALESCE(NEW.quantity, 1.0),
          unit_price = COALESCE(NEW.unit_price, NEW.amount),
          total_amount = ROUND(
            COALESCE(NEW.quantity, 1.0) * COALESCE(NEW.unit_price, NEW.amount),
            2
          ),
          amount = ROUND(
            COALESCE(NEW.quantity, 1.0) * COALESCE(NEW.unit_price, NEW.amount),
            2
          )
        WHERE id = NEW.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS expenses_recalculate_after_update
      AFTER UPDATE OF quantity, unit_price ON expenses
      BEGIN
        UPDATE expenses SET
          total_amount = ROUND(NEW.quantity * NEW.unit_price, 2),
          amount = ROUND(NEW.quantity * NEW.unit_price, 2)
        WHERE id = NEW.id;
      END
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE daily_logs ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS materials_and_equipment (
          id TEXT PRIMARY KEY,
          log_id TEXT NOT NULL,
          item_name TEXT NOT NULL,
          quantity REAL NOT NULL,
          unit TEXT,
          category TEXT NOT NULL DEFAULT 'material',
          FOREIGN KEY (log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await _createV3Tables(db);
      for (final col in [
        'serial_no INTEGER',
        'description TEXT',
        'unit TEXT',
        'unit_price REAL',
        'total_amount REAL',
        'month TEXT',
      ]) {
        try {
          await db.execute('ALTER TABLE expenses ADD COLUMN $col');
        } catch (_) {}
      }
      await db.execute('''
        UPDATE expenses SET
          total_amount = COALESCE(total_amount, amount),
          unit_price = COALESCE(unit_price, amount),
          description = COALESCE(description, note),
          month = COALESCE(month, substr(date, 1, 7))
        WHERE total_amount IS NULL OR unit_price IS NULL OR description IS NULL OR month IS NULL
      ''');
    }
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
    if (oldVersion < 5) {
      await _createV5Tables(db);
    }
    if (oldVersion < 6) {
      await _createV6Tables(db);
    }
    if (oldVersion < 7) {
      await _createV7Tables(db, isUpgrade: true);
    }
  }

  // ---------- Projects ----------
  Future<void> insertProject(Project p) async {
    final db = await database;
    await db.insert('projects', p.toMap());
  }

  Future<List<Project>> getProjects() async {
    final db = await database;
    final rows = await db.query('projects', orderBy: 'createdAt DESC');
    return rows.map((r) => Project.fromMap(r)).toList();
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Sites ----------
  Future<void> insertSite(Site s) async {
    final db = await database;
    await db.insert('sites', s.toMap());
  }

  Future<List<Site>> getSitesForProject(String projectId) async {
    final db = await database;
    final rows = await db.query(
      'sites',
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'createdAt DESC',
    );
    return rows.map((r) => Site.fromMap(r)).toList();
  }

  Future<Site?> getSiteById(String id) async {
    final db = await database;
    final rows = await db.query(
      'sites',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? Site.fromMap(rows.first) : null;
  }

  Future<void> deleteSite(String id) async {
    final db = await database;
    await db.delete('sites', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Daily Logs ----------
  Future<void> insertDailyLog(DailyLog log) async {
    final db = await database;
    await db.insert('daily_logs', log.toMap());
  }

  Future<List<DailyLog>> getLogsForSite(String siteId) async {
    final db = await database;
    final rows = await db.query(
      'daily_logs',
      where: 'siteId = ?',
      whereArgs: [siteId],
      orderBy: 'date DESC',
    );
    return rows.map((r) => DailyLog.fromMap(r)).toList();
  }

  Future<void> deleteDailyLog(String id) async {
    final db = await database;
    await db.delete('daily_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDailyLog(DailyLog log) async {
    final db = await database;
    await db.update(
      'daily_logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<void> markAllLogsSynced() async {
    final db = await database;
    await db.update('daily_logs', {'is_synced': 1});
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM daily_logs WHERE is_synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM daily_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------- Materials & Equipment ----------
  Future<void> insertMaterialItem(MaterialItem item) async {
    final db = await database;
    await db.insert('materials_and_equipment', item.toMap());
  }

  Future<List<MaterialItem>> getMaterialsForLog(String logId) async {
    final db = await database;
    final rows = await db.query(
      'materials_and_equipment',
      where: 'log_id = ?',
      whereArgs: [logId],
    );
    return rows.map((r) => MaterialItem.fromMap(r)).toList();
  }

  Future<List<MaterialItem>> getMaterialsForSite(String siteId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT m.* FROM materials_and_equipment m
      INNER JOIN daily_logs l ON m.log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date DESC
    ''',
      [siteId],
    );
    return rows.map((r) => MaterialItem.fromMap(r)).toList();
  }

  Future<void> deleteMaterialItem(String id) async {
    final db = await database;
    await db.delete(
      'materials_and_equipment',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMaterialsForLog(String logId) async {
    final db = await database;
    await db.delete(
      'materials_and_equipment',
      where: 'log_id = ?',
      whereArgs: [logId],
    );
  }

  // ---------- Expenses ----------
  Future<void> insertExpense(Expense e) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('expenses', e.toMap());
      await _syncCashFloatTotals(txn, e.siteId, _dateKey(e.date));
    });
  }

  Future<List<Expense>> getExpensesForSite(String siteId) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'siteId = ?',
      whereArgs: [siteId],
      orderBy: 'date DESC',
    );
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<List<Expense>> getExpensesForProject(String projectId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT e.* FROM expenses e
      INNER JOIN sites s ON e.siteId = s.id
      WHERE s.projectId = ?
      ORDER BY e.date DESC
    ''',
      [projectId],
    );
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<double> getTotalExpensesForProject(String projectId) async {
    final expenses = await getExpensesForProject(projectId);
    return expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'expenses',
        columns: ['siteId', 'date'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.delete('expenses', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        await _syncCashFloatTotals(
          txn,
          rows.first['siteId'] as String,
          (rows.first['date'] as String).substring(0, 10),
        );
      }
    });
  }

  Future<void> updateExpense(Expense e) async {
    final db = await database;
    await db.transaction((txn) async {
      final previous = await txn.query(
        'expenses',
        columns: ['siteId', 'date'],
        where: 'id = ?',
        whereArgs: [e.id],
        limit: 1,
      );
      await txn.update(
        'expenses',
        e.toMap(),
        where: 'id = ?',
        whereArgs: [e.id],
      );
      if (previous.isNotEmpty) {
        await _syncCashFloatTotals(
          txn,
          previous.first['siteId'] as String,
          (previous.first['date'] as String).substring(0, 10),
        );
      }
      await _syncCashFloatTotals(txn, e.siteId, _dateKey(e.date));
    });
  }

  /// Commits a multi-line expense entry and its cash reconciliation as one
  /// atomic unit. A failure leaves neither partial ledger lines nor a partial
  /// float record behind.
  Future<CashFloat> saveExpenseBatchAndReconciliation({
    required List<Expense> expenses,
    required CashFloat cashFloat,
  }) async {
    if (expenses.isEmpty) {
      throw ArgumentError.value(expenses, 'expenses', 'Cannot be empty');
    }
    final entryDate = _dateKey(cashFloat.date);
    if (expenses.any(
      (e) => e.siteId != cashFloat.siteId || _dateKey(e.date) != entryDate,
    )) {
      throw ArgumentError('Every expense must match the float site and date');
    }

    final db = await database;
    return db.transaction((txn) async {
      final existingRows = await txn.query(
        'cash_floats',
        where: 'site_id = ? AND entry_date = ?',
        whereArgs: [cashFloat.siteId, entryDate],
        limit: 1,
      );
      final floatId = existingRows.isEmpty
          ? cashFloat.id
          : existingRows.first['id'] as String;
      final initialFloat = CashFloat(
        id: floatId,
        siteId: cashFloat.siteId,
        date: cashFloat.date,
        openingBalance: cashFloat.openingBalance,
        floatReceived: cashFloat.floatReceived,
        totalExpenses: 0,
        reportedClosingBalance: cashFloat.reportedClosingBalance,
        notes: cashFloat.notes,
      );
      if (existingRows.isEmpty) {
        await txn.insert('cash_floats', initialFloat.toMap());
      } else {
        await txn.update(
          'cash_floats',
          initialFloat.toMap(),
          where: 'id = ?',
          whereArgs: [floatId],
        );
      }

      for (final expense in expenses) {
        final row = expense.toMap()..['daily_float_id'] = floatId;
        await txn.insert('expenses', row);
      }
      await _syncCashFloatTotals(txn, cashFloat.siteId, entryDate);
      final savedRows = await txn.query(
        'cash_floats',
        where: 'id = ?',
        whereArgs: [floatId],
        limit: 1,
      );
      return CashFloat.fromMap(savedRows.first);
    });
  }

  Future<void> insertExpenseBatch(List<Expense> expenses) async {
    if (expenses.isEmpty) return;
    final siteId = expenses.first.siteId;
    final entryDate = _dateKey(expenses.first.date);
    if (expenses.any(
      (expense) =>
          expense.siteId != siteId || _dateKey(expense.date) != entryDate,
    )) {
      throw ArgumentError('Every expense in a batch must share site and date');
    }
    final db = await database;
    await db.transaction((txn) async {
      final floatRows = await txn.query(
        'cash_floats',
        columns: ['id'],
        where: 'site_id = ? AND entry_date = ?',
        whereArgs: [siteId, entryDate],
        limit: 1,
      );
      final floatId = floatRows.isEmpty
          ? null
          : floatRows.first['id'] as String;
      for (final expense in expenses) {
        final row = expense.toMap()..['daily_float_id'] = floatId;
        await txn.insert('expenses', row);
      }
      await _syncCashFloatTotals(txn, siteId, entryDate);
    });
  }

  Future<int> getNextExpenseSerialNo(String siteId, String monthKey) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(serial_no) AS m FROM expenses WHERE siteId = ? AND month = ?',
      [siteId, monthKey],
    );
    final max = result.first['m'] as int?;
    return (max ?? 0) + 1;
  }

  // ---------- NEW: expense queries needed by analytics & cash float ----------
  Future<List<Expense>> getExpensesForSiteAndDate(
    String siteId,
    String dateIso,
  ) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'siteId = ? AND date LIKE ?',
      whereArgs: [siteId, '$dateIso%'],
      orderBy: 'serial_no ASC',
    );
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<double> getTotalExpensesForSiteAndDate(
    String siteId,
    String dateIso,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT SUM(total_amount) as total FROM expenses
      WHERE siteId = ? AND date LIKE ?
    ''',
      [siteId, '$dateIso%'],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Expense>> getExpensesByMonth(String siteId, String month) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'siteId = ? AND month = ?',
      whereArgs: [siteId, month],
      orderBy: 'date ASC, serial_no ASC',
    );
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<Map<String, double>> getExpenseTotalsByCategory(String siteId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT category, SUM(total_amount) as total
      FROM expenses WHERE siteId = ? GROUP BY category
    ''',
      [siteId],
    );
    return {
      for (var r in result)
        r['category'] as String: (r['total'] as num).toDouble(),
    };
  }

  Future<List<Expense>> getExpensesForSiteInRange(
    String siteId, {
    required DateTime startDate,
    required DateTime endDate,
    Set<ExpenseCategory> categories = const {},
    String search = '',
  }) async {
    final db = await database;
    final where = <String>['siteId = ?', 'substr(date, 1, 10) BETWEEN ? AND ?'];
    final args = <Object?>[siteId, _dateKey(startDate), _dateKey(endDate)];
    if (categories.isNotEmpty) {
      where.add(
        'category IN (${List.filled(categories.length, '?').join(',')})',
      );
      args.addAll(categories.map((category) => category.name));
    }
    final normalizedSearch = search.trim().toLowerCase();
    if (normalizedSearch.isNotEmpty) {
      where.add('''
        LOWER(COALESCE(description, '') || ' ' || COALESCE(unit, '') || ' ' || COALESCE(note, ''))
        LIKE ?
      ''');
      args.add('%$normalizedSearch%');
    }
    final rows = await db.query(
      'expenses',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date ASC, serial_no ASC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<Map<String, Map<ExpenseCategory, double>>> getMonthlyCategoryMatrix(
    String siteId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT month, category, SUM(total_amount) AS total
      FROM expenses
      WHERE siteId = ?
      GROUP BY month, category
      ORDER BY month ASC
    ''',
      [siteId],
    );
    final matrix = <String, Map<ExpenseCategory, double>>{};
    for (final row in rows) {
      final month = row['month'] as String? ?? 'Unknown';
      final category = ExpenseCategoryX.fromLabelOrName(
        row['category'] as String,
      );
      matrix.putIfAbsent(month, () => <ExpenseCategory, double>{})[category] =
          (row['total'] as num?)?.toDouble() ?? 0;
    }
    return matrix;
  }

  // ---------- Workers ----------
  Future<void> insertWorker(Worker w) async {
    final db = await database;
    await db.insert('workers', w.toMap());
  }

  Future<void> updateWorker(Worker w) async {
    final db = await database;
    await db.update('workers', w.toMap(), where: 'id = ?', whereArgs: [w.id]);
  }

  Future<List<Worker>> getWorkersForSite(
    String siteId, {
    bool activeOnly = true,
  }) async {
    final db = await database;
    final rows = await db.query(
      'workers',
      where: activeOnly ? 'site_id = ? AND is_active = 1' : 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'name ASC',
    );
    return rows.map((r) => Worker.fromMap(r)).toList();
  }

  Future<void> deactivateWorker(String id) async {
    final db = await database;
    await db.update(
      'workers',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWorker(String id) async {
    final db = await database;
    await db.delete('workers', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Attendance ----------
  Future<void> upsertAttendance(Attendance a) async {
    final db = await database;
    await db.insert(
      'daily_attendance',
      a.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> bulkUpsertAttendance(List<Attendance> records) async {
    final db = await database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert(
        'daily_attendance',
        r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Attendance>> getAttendanceForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query(
      'daily_attendance',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
    return rows.map((r) => Attendance.fromMap(r)).toList();
  }

  Future<void> deleteAttendanceForLog(String dailyLogId) async {
    final db = await database;
    await db.delete(
      'daily_attendance',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
  }

  Future<Map<String, int>> getAttendanceSummaryForLog(String dailyLogId) async {
    final rows = await getAttendanceForLog(dailyLogId);
    final summary = <String, int>{'Present': 0, 'Absent': 0, 'Half-Day': 0};
    for (final r in rows) {
      summary[r.status.dbValue] = (summary[r.status.dbValue] ?? 0) + 1;
    }
    return summary;
  }

  // ---------- Material Stock Logs ----------
  Future<void> insertMaterialStockLog(MaterialStockLog m) async {
    final db = await database;
    await db.insert('material_stock_logs', m.toMap());
  }

  Future<void> updateMaterialStockLog(MaterialStockLog m) async {
    final db = await database;
    await db.update(
      'material_stock_logs',
      m.toMap(),
      where: 'id = ?',
      whereArgs: [m.id],
    );
  }

  Future<List<MaterialStockLog>> getMaterialStockLogsForLog(
    String dailyLogId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'material_stock_logs',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
    return rows.map((r) => MaterialStockLog.fromMap(r)).toList();
  }

  Future<double?> getLastClosingBalance(String siteId, String itemName) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT m.closing_balance AS cb FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ? AND m.item_name = ?
      ORDER BY l.date DESC LIMIT 1
    ''',
      [siteId, itemName],
    );
    if (rows.isEmpty) return null;
    return (rows.first['cb'] as num?)?.toDouble();
  }

  Future<void> deleteMaterialStockLog(String id) async {
    final db = await database;
    await db.delete('material_stock_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMaterialStockLogsForLog(String dailyLogId) async {
    final db = await database;
    await db.delete(
      'material_stock_logs',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
  }

  // ---------- Equipment Dipping Logs ----------
  Future<void> insertEquipmentDippingLog(EquipmentDippingLog e) async {
    final db = await database;
    await db.insert('equipment_dipping_logs', e.toMap());
  }

  Future<void> updateEquipmentDippingLog(EquipmentDippingLog e) async {
    final db = await database;
    await db.update(
      'equipment_dipping_logs',
      e.toMap(),
      where: 'id = ?',
      whereArgs: [e.id],
    );
  }

  Future<List<EquipmentDippingLog>> getEquipmentDippingLogsForLog(
    String dailyLogId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'equipment_dipping_logs',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
    return rows.map((r) => EquipmentDippingLog.fromMap(r)).toList();
  }

  Future<void> deleteEquipmentDippingLog(String id) async {
    final db = await database;
    await db.delete('equipment_dipping_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteEquipmentDippingLogsForLog(String dailyLogId) async {
    final db = await database;
    await db.delete(
      'equipment_dipping_logs',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
  }

  /// Every material stock row for a site, each tagged with its log's date —
  /// used for exports that need a per-day ledger rather than one log at a time.
  Future<List<Map<String, dynamic>>> getMaterialStockLogsForSite(
    String siteId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT m.*, l.date AS log_date FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC, m.item_name ASC
    ''',
      [siteId],
    );
  }

  /// Every equipment dipping row for a site, each tagged with its log's date.
  Future<List<Map<String, dynamic>>> getEquipmentDippingLogsForSite(
    String siteId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT e.*, l.date AS log_date FROM equipment_dipping_logs e
      INNER JOIN daily_logs l ON e.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC, e.equipment_name ASC
    ''',
      [siteId],
    );
  }

  /// Every ad-hoc diesel activity issuance row for a site, tagged with date.
  Future<List<Map<String, dynamic>>> getDieselActivityForSite(
    String siteId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT d.*, l.date AS log_date FROM diesel_activity_issuance d
      INNER JOIN daily_logs l ON d.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC
    ''',
      [siteId],
    );
  }

  // ---------- Concrete Pours / Slump Test QC ----------
  Future<void> insertConcretePour(ConcretePour c) async {
    final db = await database;
    await db.insert('concrete_pours', c.toMap());
  }

  Future<void> updateConcretePour(ConcretePour c) async {
    final db = await database;
    await db.update(
      'concrete_pours',
      c.toMap(),
      where: 'id = ?',
      whereArgs: [c.id],
    );
  }

  Future<List<ConcretePour>> getConcretePoursForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query(
      'concrete_pours',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
    return rows.map((r) => ConcretePour.fromMap(r)).toList();
  }

  Future<void> deleteConcretePour(String id) async {
    final db = await database;
    await db.delete('concrete_pours', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteConcretePoursForLog(String dailyLogId) async {
    final db = await database;
    await db.delete(
      'concrete_pours',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
  }

  /// Every concrete pour row for a site, each tagged with its log's date —
  /// used by the PDF/Excel report engines for the QC table.
  Future<List<Map<String, dynamic>>> getConcretePoursForSite(
    String siteId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT c.*, l.date AS log_date FROM concrete_pours c
      INNER JOIN daily_logs l ON c.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC, c.element_name ASC
    ''',
      [siteId],
    );
  }

  // ---------- Diesel Activity Issuance (non-dipped machines/activities) ----------
  Future<void> insertDieselActivityIssuance(DieselActivityIssuance d) async {
    final db = await database;
    await db.insert('diesel_activity_issuance', d.toMap());
  }

  Future<List<DieselActivityIssuance>> getDieselActivityForLog(
    String dailyLogId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'diesel_activity_issuance',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
    return rows.map((r) => DieselActivityIssuance.fromMap(r)).toList();
  }

  Future<void> deleteDieselActivityForLog(String dailyLogId) async {
    final db = await database;
    await db.delete(
      'diesel_activity_issuance',
      where: 'daily_log_id = ?',
      whereArgs: [dailyLogId],
    );
  }

  /// Sitewide diesel totals across every daily log for a site — used by
  /// exports (Excel/PDF) to show cumulative received/issued/balance rather
  /// than just a single day's snapshot.
  Future<Map<String, double>> getDieselTotalsForSite(String siteId) async {
    final db = await database;
    final materialRows = await db.rawQuery(
      '''
      SELECT SUM(m.received) AS recv FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ? AND m.item_name = 'Diesel'
    ''',
      [siteId],
    );
    final machineRows = await db.rawQuery(
      '''
      SELECT SUM(e.diesel_issued_litres) AS issued FROM equipment_dipping_logs e
      INNER JOIN daily_logs l ON e.daily_log_id = l.id
      WHERE l.siteId = ?
    ''',
      [siteId],
    );
    final activityRows = await db.rawQuery(
      '''
      SELECT SUM(d.litres_issued) AS issued FROM diesel_activity_issuance d
      INNER JOIN daily_logs l ON d.daily_log_id = l.id
      WHERE l.siteId = ?
    ''',
      [siteId],
    );
    final openingBal = await getLastClosingBalance(siteId, 'Diesel') ?? 0.0;
    final received = (materialRows.first['recv'] as num?)?.toDouble() ?? 0.0;
    final issuedMachines =
        (machineRows.first['issued'] as num?)?.toDouble() ?? 0.0;
    final issuedActivities =
        (activityRows.first['issued'] as num?)?.toDouble() ?? 0.0;
    return {
      'opening': openingBal,
      'received': received,
      'issuedMachines': issuedMachines,
      'issuedActivities': issuedActivities,
      'balance': openingBal + received - issuedMachines - issuedActivities,
    };
  }

  /// Sitewide reinforcement (rebar) totals per size across every daily log.
  Future<Map<String, Map<String, double>>> getReinforcementTotalsForSite(
    String siteId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT m.item_name AS item, SUM(m.received) AS recv, SUM(m.issued) AS issued
      FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ? AND m.item_name LIKE '%Rebar%'
      GROUP BY m.item_name
    ''',
      [siteId],
    );
    final result = <String, Map<String, double>>{};
    for (final r in rows) {
      final item = r['item'] as String;
      final closing = await getLastClosingBalance(siteId, item) ?? 0.0;
      result[item] = {
        'received': (r['recv'] as num?)?.toDouble() ?? 0.0,
        'issued': (r['issued'] as num?)?.toDouble() ?? 0.0,
        'closing': closing,
      };
    }
    return result;
  }

  // ---------- Google Sheets Sync Link ----------
  Future<Map<String, dynamic>?> getSheetSync(String siteId) async {
    final db = await database;
    final rows = await db.query(
      'sheet_sync',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> upsertSheetSync({
    required String siteId,
    String? spreadsheetId,
    String? spreadsheetUrl,
    bool? autoSync,
    String? lastSyncedAt,
    String? lastSyncError,
  }) async {
    final db = await database;
    final existing = await getSheetSync(siteId);
    final row = {
      'site_id': siteId,
      'spreadsheet_id': spreadsheetId ?? existing?['spreadsheet_id'],
      'spreadsheet_url': spreadsheetUrl ?? existing?['spreadsheet_url'],
      'auto_sync': (autoSync ?? ((existing?['auto_sync'] as int?) == 1))
          ? 1
          : 0,
      'last_synced_at': lastSyncedAt ?? existing?['last_synced_at'],
      'last_sync_error': lastSyncError,
    };
    if (existing != null) {
      await db.update(
        'sheet_sync',
        row,
        where: 'site_id = ?',
        whereArgs: [siteId],
      );
    } else {
      await db.insert('sheet_sync', row);
    }
  }

  // ---------- Cash Floats ----------
  Future<void> insertCashFloat(CashFloat c) async {
    await upsertCashFloat(c);
  }

  Future<void> updateCashFloat(CashFloat c) async {
    await upsertCashFloat(c);
  }

  Future<CashFloat> upsertCashFloat(CashFloat cashFloat) async {
    final db = await database;
    return db.transaction((txn) async {
      final entryDate = _dateKey(cashFloat.date);
      final existing = await txn.query(
        'cash_floats',
        where: 'site_id = ? AND entry_date = ?',
        whereArgs: [cashFloat.siteId, entryDate],
        limit: 1,
      );
      final totalRows = await txn.rawQuery(
        '''
        SELECT SUM(total_amount) AS total FROM expenses
        WHERE siteId = ? AND substr(date, 1, 10) = ?
      ''',
        [cashFloat.siteId, entryDate],
      );
      final normalized = CashFloat(
        id: existing.isEmpty ? cashFloat.id : existing.first['id'] as String,
        siteId: cashFloat.siteId,
        date: cashFloat.date,
        openingBalance: cashFloat.openingBalance,
        floatReceived: cashFloat.floatReceived,
        totalExpenses: (totalRows.first['total'] as num?)?.toDouble() ?? 0,
        reportedClosingBalance: cashFloat.reportedClosingBalance,
        notes: cashFloat.notes,
      );
      if (existing.isEmpty) {
        await txn.insert('cash_floats', normalized.toMap());
      } else {
        await txn.update(
          'cash_floats',
          normalized.toMap(),
          where: 'id = ?',
          whereArgs: [normalized.id],
        );
      }
      await txn.update(
        'expenses',
        {'daily_float_id': normalized.id},
        where: 'siteId = ? AND substr(date, 1, 10) = ?',
        whereArgs: [normalized.siteId, entryDate],
      );
      return normalized;
    });
  }

  Future<List<CashFloat>> getCashFloatsForSite(String siteId) async {
    final db = await database;
    final rows = await db.query(
      'cash_floats',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'entry_date DESC',
    );
    return rows.map((r) => CashFloat.fromMap(r)).toList();
  }

  Future<CashFloat?> getLatestCashFloat(String siteId) async {
    final rows = await getCashFloatsForSite(siteId);
    return rows.isEmpty ? null : rows.first;
  }

  Future<CashFloat?> getCashFloatBySiteAndDate(
    String siteId,
    String dateIso,
  ) async {
    final db = await database;
    final rows = await db.query(
      'cash_floats',
      where: 'site_id = ? AND entry_date = ?',
      whereArgs: [siteId, dateIso.substring(0, 10)],
      limit: 1,
    );
    return rows.isNotEmpty ? CashFloat.fromMap(rows.first) : null;
  }

  Future<CashFloat?> getCashFloatBeforeDate(
    String siteId,
    String dateIso,
  ) async {
    final db = await database;
    final rows = await db.query(
      'cash_floats',
      where: 'site_id = ? AND entry_date < ?',
      whereArgs: [siteId, dateIso.substring(0, 10)],
      orderBy: 'entry_date DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CashFloat.fromMap(rows.first);
  }

  Future<double> getTotalFloatReceived(String siteId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT SUM(float_received) as total FROM cash_floats WHERE site_id = ?
    ''',
      [siteId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> deleteCashFloat(String id) async {
    final db = await database;
    await db.delete('cash_floats', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _syncCashFloatTotals(
    DatabaseExecutor executor,
    String siteId,
    String entryDate,
  ) async {
    final rows = await executor.query(
      'cash_floats',
      where: 'site_id = ? AND entry_date = ?',
      whereArgs: [siteId, entryDate],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final totalRows = await executor.rawQuery(
      '''
      SELECT SUM(total_amount) AS total FROM expenses
      WHERE siteId = ? AND substr(date, 1, 10) = ?
    ''',
      [siteId, entryDate],
    );
    final old = CashFloat.fromMap(rows.first);
    final updated = CashFloat(
      id: old.id,
      siteId: old.siteId,
      date: old.date,
      openingBalance: old.openingBalance,
      floatReceived: old.floatReceived,
      totalExpenses: (totalRows.first['total'] as num?)?.toDouble() ?? 0,
      reportedClosingBalance: old.reportedClosingBalance,
      notes: old.notes,
    );
    await executor.update(
      'cash_floats',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await executor.update(
      'expenses',
      {'daily_float_id': updated.id},
      where: 'siteId = ? AND substr(date, 1, 10) = ?',
      whereArgs: [siteId, entryDate],
    );
  }
}
