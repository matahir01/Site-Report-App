import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_daily_log/db/database_helper.dart';
import 'package:site_daily_log/models/cash_float.dart';
import 'package:site_daily_log/models/expense.dart';
import 'package:site_daily_log/models/project.dart';
import 'package:site_daily_log/models/site.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'site_daily_log_db_test_',
    );
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('fresh schema seeds the exact ten locked expense categories', () async {
    final helper = _helperAt(temporaryDirectory, 'fresh.db');
    addTearDown(helper.closeForRestore);
    final db = await helper.database;

    final rows = await db.query('categories', orderBy: 'sort_order ASC');

    expect(rows.map((row) => row['name']), [
      'Fuel & Lubricants',
      'Materials',
      'Wages, Allowances & Advances',
      'Transport',
      'Repairs & Maintenance',
      'Tools & Equipment',
      'Medical Expenses',
      'Labour',
      'Site Welfare & Safety',
      'Other / Miscellaneous',
    ]);
  });

  test('batch expenses and float reconciliation commit atomically', () async {
    final helper = _helperAt(temporaryDirectory, 'batch.db');
    addTearDown(helper.closeForRestore);
    await _seedProjectAndSite(helper);
    final date = DateTime(2026, 9, 24, 12);

    final saved = await helper.saveExpenseBatchAndReconciliation(
      expenses: [
        Expense(
          id: 'expense-1',
          siteId: 'site-1',
          date: date,
          category: ExpenseCategory.materials,
          amount: 2000,
          quantity: 2,
          unitPrice: 1000,
          description: 'Cement handling',
        ),
        Expense(
          id: 'expense-2',
          siteId: 'site-1',
          date: date,
          category: ExpenseCategory.transport,
          amount: 3300,
          description: 'Delivery transport',
        ),
      ],
      cashFloat: CashFloat(
        id: 'float-1',
        siteId: 'site-1',
        date: date,
        floatReceived: 100000,
        reportedClosingBalance: 94700,
      ),
    );

    expect(saved.totalExpenses, 5300);
    expect(saved.expectedClosingBalance, 94700);
    expect(saved.variance, 0);
    expect(saved.status, CashFloatStatus.ok);

    final expenses = await helper.getExpensesForSiteAndDate(
      'site-1',
      '2026-09-24',
    );
    expect(expenses, hasLength(2));
    expect(expenses.map((expense) => expense.dailyFloatId).toSet(), {
      'float-1',
    });
  });

  test(
    'v6 migration backfills categories, quantities and unique dates',
    () async {
      final path = '${temporaryDirectory.path}/migration.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, version) async {
            await _createLegacyV6Schema(db);
          },
        ),
      );
      await legacy.insert('projects', {
        'id': 'project-1',
        'name': 'Legacy project',
        'client': 'Legacy client',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      await legacy.insert('expenses', {
        'id': 'expense-1',
        'siteId': 'site-1',
        'date': DateTime(2026, 9, 24).toIso8601String(),
        'category': 'fuelAndLubricants',
        'amount': 3000.0,
        'unit_price': 1200.0,
        'total_amount': 3000.0,
        'month': '2026-09',
      });
      for (final id in ['float-old', 'float-new']) {
        await legacy.insert('cash_floats', {
          'id': id,
          'site_id': 'site-1',
          'date': DateTime(2026, 9, 24).toIso8601String(),
          'opening_balance': 0.0,
          'float_received': 10000.0,
          'total_expenses': 3000.0,
          'expected_closing_balance': 7000.0,
          'reported_closing_balance': 7000.0,
          'variance': 0.0,
          'status': 'OK',
        });
      }
      await legacy.close();

      final helper = DatabaseHelper.forTesting(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(helper.closeForRestore);
      final upgraded = await helper.database;

      final projects = await upgraded.query('projects');
      expect(projects.single['project_name'], 'Legacy project');
      expect(projects.single['client_name'], 'Legacy client');

      final expenses = await upgraded.query('expenses');
      expect(expenses.single['category_id'], 1);
      expect(expenses.single['quantity'], 2.5);
      expect(expenses.single['daily_float_id'], 'float-new');

      final floats = await upgraded.query('cash_floats');
      expect(floats, hasLength(1));
      expect(floats.single['entry_date'], '2026-09-24');
    },
  );
}

DatabaseHelper _helperAt(Directory directory, String name) {
  return DatabaseHelper.forTesting(
    factory: databaseFactoryFfi,
    path: '${directory.path}/$name',
  );
}

Future<void> _seedProjectAndSite(DatabaseHelper helper) async {
  await helper.insertProject(
    Project(
      id: 'project-1',
      name: 'Road Rehabilitation',
      client: 'Client',
      createdAt: DateTime(2026, 1, 1),
    ),
  );
  await helper.insertSite(
    Site(
      id: 'site-1',
      projectId: 'project-1',
      name: 'Bajoga Site',
      createdAt: DateTime(2026, 1, 1),
    ),
  );
}

Future<void> _createLegacyV6Schema(Database db) async {
  await db.execute('''
    CREATE TABLE projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      client TEXT,
      createdAt TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE expenses (
      id TEXT PRIMARY KEY,
      siteId TEXT NOT NULL,
      date TEXT NOT NULL,
      category TEXT NOT NULL,
      amount REAL NOT NULL,
      note TEXT,
      receiptPhotoPath TEXT,
      serial_no INTEGER,
      description TEXT,
      unit TEXT,
      unit_price REAL,
      total_amount REAL,
      month TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE cash_floats (
      id TEXT PRIMARY KEY,
      site_id TEXT NOT NULL,
      date TEXT NOT NULL,
      opening_balance REAL NOT NULL DEFAULT 0.0,
      float_received REAL NOT NULL DEFAULT 0.0,
      total_expenses REAL NOT NULL DEFAULT 0.0,
      expected_closing_balance REAL NOT NULL DEFAULT 0.0,
      reported_closing_balance REAL NOT NULL DEFAULT 0.0,
      variance REAL NOT NULL DEFAULT 0.0,
      status TEXT NOT NULL DEFAULT 'OK',
      notes TEXT
    )
  ''');
}
