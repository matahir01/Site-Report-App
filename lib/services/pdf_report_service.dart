import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/database_helper.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/concrete_pour.dart';
import '../models/cash_float.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';

/// On-device PDF report generation for sites, projects, and individual
/// daily logs.
class PdfReportService {
  static String _categoryLabel(ExpenseCategory c) {
    return c.label;
  }

  // ---- Naira-glyph fix (Option 2: custom TTF fonts) ----
  //
  // The `pdf` package's built-in base14 fonts (Helvetica etc.) have no ₦
  // glyph, so any CurrencyFormatter.format() output rendered in the default
  // font shows a missing-glyph box instead of the Naira sign. Roboto has a
  // ₦ glyph, so we load it once via rootBundle and set it as the document's
  // base/bold theme font — every pw.Text widget that doesn't explicitly
  // override its font then inherits Roboto automatically, including
  // headers, tables, and the cash-flow summary card.
  //
  // Cached after first load so repeated report generation in one app
  // session doesn't re-read the asset bytes each time.
  // Shared palette so the plain site/project reports can match the styled
  // daily-log report instead of rendering as bare text.
  static final PdfColor _navy = PdfColor.fromHex('#1A365D');
  static final PdfColor _steelBlue = PdfColor.fromHex('#2B6CB0');
  static final PdfColor _iceBlue = PdfColor.fromHex('#EBF8FF');
  static final PdfColor _slateBorder = PdfColors.blueGrey200;

  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> _loadTheme() async {
    final cached = _cachedTheme;
    if (cached != null) return cached;
    final regularData = await rootBundle.load(
      'assets/fonts/Roboto-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    _cachedTheme = theme;
    return theme;
  }


  static Future<File> generateSiteReport({
    required Project project,
    required Site site,
    required List<DailyLog> logs,
    required List<Expense> expenses,
  }) async {
    final theme = await _loadTheme();
    final doc = pw.Document(theme: theme);
    final floats = await DatabaseHelper.instance.getCashFloatsForSite(site.id);

    _addWorkbookMirrorReport(
      doc: doc,
      reportType: 'SITE AUDIT REPORT',
      title: site.name,
      subtitle: project.name,
      detailLine: site.address ?? project.client ?? 'Construction site',
      sites: [site],
      logsBySite: {site.id: logs},
      expenses: expenses,
      cashFloats: floats,
      includeSite: false,
    );

    return _saveDoc(doc, '${site.name}_audit_report');
  }

  static Future<File> generateProjectReport({
    required Project project,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required Map<String, List<Expense>> expensesBySite,
  }) async {
    final theme = await _loadTheme();
    final doc = pw.Document(theme: theme);
    final expenses = expensesBySite.values.expand((items) => items).toList();
    final cashFloats = <CashFloat>[];
    for (final site in sites) {
      cashFloats.addAll(
        await DatabaseHelper.instance.getCashFloatsForSite(site.id),
      );
    }

    _addWorkbookMirrorReport(
      doc: doc,
      reportType: 'PROJECT AUDIT REPORT',
      title: project.name,
      subtitle: project.client ?? 'Client not recorded',
      detailLine: '${sites.length} site${sites.length == 1 ? '' : 's'}',
      sites: sites,
      logsBySite: logsBySite,
      expenses: expenses,
      cashFloats: cashFloats,
      includeSite: sites.length > 1,
    );

    return _saveDoc(doc, '${project.name}_audit_report');
  }

  static void _addWorkbookMirrorReport({
    required pw.Document doc,
    required String reportType,
    required String title,
    required String subtitle,
    required String detailLine,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required List<Expense> expenses,
    required List<CashFloat> cashFloats,
    required bool includeSite,
  }) {
    final siteNames = {for (final site in sites) site.id: site.name};
    final sortedExpenses = [...expenses]
      ..sort((a, b) => a.date.compareTo(b.date));
    final sortedFloats = [...cashFloats]
      ..sort((a, b) => a.date.compareTo(b.date));
    final grandTotal = sortedExpenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );
    final totalFloat = sortedFloats.fold<double>(
      0,
      (sum, cashFloat) => sum + cashFloat.floatReceived,
    );

    final months =
        sortedExpenses.map((expense) => expense.monthKey).toSet().toList()
          ..sort();
    final categoryTotals = <ExpenseCategory, double>{
      for (final category in ExpenseCategory.values) category: 0,
    };
    final categoryCounts = <ExpenseCategory, int>{
      for (final category in ExpenseCategory.values) category: 0,
    };
    final monthTotals = <String, double>{for (final month in months) month: 0};
    final monthCategoryTotals = <String, Map<ExpenseCategory, double>>{
      for (final month in months)
        month: {for (final category in ExpenseCategory.values) category: 0},
    };
    final dailyExpenseTotals = <String, double>{};

    for (final expense in sortedExpenses) {
      categoryTotals[expense.category] =
          categoryTotals[expense.category]! + expense.amount;
      categoryCounts[expense.category] = categoryCounts[expense.category]! + 1;
      monthTotals[expense.monthKey] =
          (monthTotals[expense.monthKey] ?? 0) + expense.amount;
      monthCategoryTotals[expense.monthKey]![expense.category] =
          monthCategoryTotals[expense.monthKey]![expense.category]! +
          expense.amount;
      final dateKey = DateFormat('yyyy-MM-dd').format(expense.date);
      final key = '${expense.siteId}|$dateKey';
      dailyExpenseTotals[key] = (dailyExpenseTotals[key] ?? 0) + expense.amount;
    }

    final latestBalanceBySite = <String, double>{};
    for (final cashFloat in sortedFloats) {
      latestBalanceBySite[cashFloat.siteId] = cashFloat.expectedClosingBalance;
    }
    final currentBalance = sortedFloats.isEmpty
        ? totalFloat - grandTotal
        : latestBalanceBySite.values.fold<double>(
            0,
            (sum, value) => sum + value,
          );

    ExpenseCategory? highestCategory;
    double highestSpend = 0;
    for (final entry in categoryTotals.entries) {
      if (entry.value > highestSpend) {
        highestCategory = entry.key;
        highestSpend = entry.value;
      }
    }

    final activeDates = sortedExpenses
        .map((expense) => DateFormat('yyyy-MM-dd').format(expense.date))
        .toSet()
        .length;
    final averageDailySpend = activeDates == 0 ? 0.0 : grandTotal / activeDates;
    final logCount = logsBySite.values.fold<int>(
      0,
      (sum, logs) => sum + logs.length,
    );

    final chartCategoryData = <String, double>{
      for (final category in ExpenseCategory.values)
        if ((categoryTotals[category] ?? 0) > 0)
          category.label: categoryTotals[category] ?? 0,
    };
    final chartMonthData = <String, double>{
      for (final month in months) month: monthTotals[month] ?? 0,
    };
    final burnDaily = <DateTime, double>{};
    for (final expense in sortedExpenses) {
      final day = DateTime(
        expense.date.year,
        expense.date.month,
        expense.date.day,
      );
      burnDaily[day] = (burnDaily[day] ?? 0) + expense.amount;
    }
    final burnDays = burnDaily.keys.toList()..sort();
    double cumulative = 0;
    final burnPoints = <MapEntry<DateTime, double>>[];
    for (final day in burnDays) {
      cumulative += burnDaily[day] ?? 0;
      burnPoints.add(MapEntry(day, cumulative));
    }

    final chartPalette = [
      _steelBlue,
      PdfColor.fromHex('#38B2AC'),
      PdfColor.fromHex('#ED8936'),
      PdfColor.fromHex('#9F7AEA'),
      PdfColor.fromHex('#48BB78'),
      PdfColor.fromHex('#F56565'),
      PdfColor.fromHex('#ECC94B'),
      PdfColor.fromHex('#718096'),
      PdfColor.fromHex('#D53F8C'),
      PdfColor.fromHex('#319795'),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) =>
            _buildReportHeader(reportType, title, subtitle, detailLine),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _sectionTitle('EXECUTIVE SUMMARY', _steelBlue),
          pw.SizedBox(height: 8),
          _buildKpiGrid([
            ['Total Spend', CurrencyFormatter.format(grandTotal)],
            ['Total Float Received', CurrencyFormatter.format(totalFloat)],
            ['Current Cash Balance', CurrencyFormatter.format(currentBalance)],
            ['Expense Items', sortedExpenses.length.toString()],
            ['Daily Reports', logCount.toString()],
            ['Active Spend Days', activeDates.toString()],
            [
              'Highest Cost Category',
              grandTotal == 0
                  ? 'No spend yet'
                  : highestCategory?.label ?? 'No spend yet',
            ],
            ['Average Daily Spend', CurrencyFormatter.format(averageDailySpend)],
          ]),
          pw.SizedBox(height: 14),
          _sectionTitle('EXPENDITURE BY CATEGORY', _steelBlue),
          pw.SizedBox(height: 8),
          if (grandTotal == 0)
            _emptyCard('No expenses recorded.')
          else
            _buildTable(
              headers: ['Category', 'Spend', 'Items', '% of Total'],
              rows: ExpenseCategory.values
                  .map(
                    (category) => [
                      category.label,
                      CurrencyFormatter.format(categoryTotals[category] ?? 0),
                      (categoryCounts[category] ?? 0).toString(),
                      grandTotal == 0
                          ? '0.0%'
                          : '${(((categoryTotals[category] ?? 0) / grandTotal) * 100).toStringAsFixed(1)}%',
                    ],
                  )
                  .toList(),
              navy: _navy,
              iceBlue: _iceBlue,
              slateBorder: _slateBorder,
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FixedColumnWidth(45),
                3: const pw.FixedColumnWidth(60),
              },
            ),
          if (chartCategoryData.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('COST DISTRIBUTION', _steelBlue),
            pw.SizedBox(height: 8),
            _pieChart(chartCategoryData, chartPalette),
          ],
          pw.NewPage(),
          _sectionTitle('CONSTRUCTION PROGRESS LOG', _steelBlue),
          pw.SizedBox(height: 8),
          for (final site in sites) ...[
            if (includeSite) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                color: _iceBlue,
                child: pw.Text(
                  site.name,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
            ],
            if ((logsBySite[site.id] ?? const <DailyLog>[]).isEmpty)
              _emptyCard('No daily logs recorded for ${site.name}.')
            else
              ...(logsBySite[site.id] ?? const <DailyLog>[]).map(
                (log) => _logBlock(log, DateFormat.yMMMd()),
              ),
            pw.SizedBox(height: 8),
          ],
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _buildReportHeader(
          'PDF MIRROR OF EXCEL AUDIT WORKBOOK',
          title,
          subtitle,
          'Financial schedules and audit trail',
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _sectionTitle('1. REPORT GUIDE / AUDIT BASIS', _steelBlue),
          pw.SizedBox(height: 8),
          _buildTable(
            headers: ['Workbook section', 'PDF equivalent / audit rule'],
            rows: [
              [
                'Daily Log',
                'Detailed expense ledger. Every amount is Quantity x Unit Price; use Quantity = 1 for lump-sum costs.',
              ],
              [
                'Monthly Summary',
                'Category-by-month matrix with category totals and monthly totals.',
              ],
              [
                'Overall Summary',
                'Category totals, item counts, percentage share and management KPIs.',
              ],
              [
                'Cash Flow',
                'Expected Closing = Opening Balance + Float Received - Daily Expenses.',
              ],
              [
                'Variance',
                'Reported Closing - Expected Closing. Exactly ${CurrencyFormatter.format(0)} is OK; every other value is CHECK / MISMATCH.',
              ],
              [
                'Negative balance',
                'Represents site deficit / engineer out-of-pocket advance carried forward until later funding offsets it.',
              ],
              [
                'Charts',
                'Monthly spend, category distribution and cumulative expenditure trend.',
              ],
            ],
            navy: _navy,
            iceBlue: _iceBlue,
            slateBorder: _slateBorder,
            columnWidths: {
              0: const pw.FixedColumnWidth(110),
              1: const pw.FlexColumnWidth(1),
            },
          ),
          pw.NewPage(),
          _sectionTitle('2. DETAILED EXPENSE LEDGER', _steelBlue),
          pw.SizedBox(height: 8),
          if (sortedExpenses.isEmpty)
            _emptyCard('No expenses recorded.')
          else
            _buildTable(
              headers: [
                'Date',
                if (includeSite) 'Site',
                'S/N',
                'Description',
                'Unit',
                'Qty',
                'Unit Price',
                'Total Amount',
                'Category',
              ],
              rows: sortedExpenses
                  .map(
                    (expense) => [
                      DateFormat('yyyy-MM-dd').format(expense.date),
                      if (includeSite)
                        siteNames[expense.siteId] ?? expense.siteId,
                      expense.serialNo?.toString() ?? '',
                      expense.displayDescription,
                      expense.unit ?? '1',
                      expense.quantity.toStringAsFixed(2),
                      CurrencyFormatter.format(
                        expense.unitPrice ?? expense.amount,
                      ),
                      CurrencyFormatter.format(expense.amount),
                      expense.category.label,
                    ],
                  )
                  .toList(),
              navy: _navy,
              iceBlue: _iceBlue,
              slateBorder: _slateBorder,
              columnWidths: {
                0: const pw.FixedColumnWidth(58),
              },
            ),
          if (sortedExpenses.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _totalBar('TOTAL EXPENDITURE', grandTotal, _navy),
          ],
          pw.NewPage(),
          _sectionTitle('3. MONTHLY SUMMARY MATRIX', _steelBlue),
          pw.SizedBox(height: 8),
          if (months.isEmpty)
            _emptyCard('No monthly expense data available.')
          else
            _buildTable(
              headers: ['Category', ...months, 'Category Total'],
              rows: [
                for (final category in ExpenseCategory.values)
                  [
                    category.label,
                    for (final month in months)
                      CurrencyFormatter.format(
                        monthCategoryTotals[month]?[category] ?? 0,
                      ),
                    CurrencyFormatter.format(categoryTotals[category] ?? 0),
                  ],
                [
                  'MONTHLY TOTAL',
                  for (final month in months)
                    CurrencyFormatter.format(monthTotals[month] ?? 0),
                  CurrencyFormatter.format(grandTotal),
                ],
              ],
              navy: _navy,
              iceBlue: _iceBlue,
              slateBorder: _slateBorder,
              columnWidths: {
                0: const pw.FixedColumnWidth(120),
              },
            ),
          pw.NewPage(),
          _sectionTitle('4. OVERALL SUMMARY & KPIs', _steelBlue),
          pw.SizedBox(height: 8),
          _buildTable(
            headers: ['Category', 'Total Spend', 'Item Count', '% of Total'],
            rows: [
              for (final category in ExpenseCategory.values)
                [
                  category.label,
                  CurrencyFormatter.format(categoryTotals[category] ?? 0),
                  (categoryCounts[category] ?? 0).toString(),
                  grandTotal == 0
                      ? '0.0%'
                      : '${(((categoryTotals[category] ?? 0) / grandTotal) * 100).toStringAsFixed(1)}%',
                ],
              [
                'TOTAL',
                CurrencyFormatter.format(grandTotal),
                sortedExpenses.length.toString(),
                grandTotal == 0 ? '0.0%' : '100.0%',
              ],
            ],
            navy: _navy,
            iceBlue: _iceBlue,
            slateBorder: _slateBorder,
          ),
          pw.SizedBox(height: 12),
          _buildKpiGrid([
            ['Total Site / Project Spend', CurrencyFormatter.format(grandTotal)],
            ['Total Float Received', CurrencyFormatter.format(totalFloat)],
            ['Current Cash Balance', CurrencyFormatter.format(currentBalance)],
            [
              'Highest Cost Category',
              grandTotal == 0
                  ? 'No spend yet'
                  : highestCategory?.label ?? 'No spend yet',
            ],
            [
              'Highest Category Share',
              grandTotal == 0
                  ? '0.0%'
                  : '${(highestSpend / grandTotal * 100).toStringAsFixed(1)}%',
            ],
            ['Average Daily Spend', CurrencyFormatter.format(averageDailySpend)],
          ]),
          pw.NewPage(),
          _sectionTitle('5. CASH FLOW & RECONCILIATION', _steelBlue),
          pw.SizedBox(height: 8),
          if (sortedFloats.isEmpty)
            _emptyCard('No cash-float reconciliations recorded.')
          else
            _buildTable(
              headers: [
                'Date',
                if (includeSite) 'Site',
                'Opening',
                'Float Top-up',
                'Daily Expenses',
                'Expected Closing',
                'Reported Closing',
                'Variance',
                'Status',
              ],
              rows: sortedFloats.map((cashFloat) {
                final date = DateFormat('yyyy-MM-dd').format(cashFloat.date);
                final daily =
                    dailyExpenseTotals['${cashFloat.siteId}|$date'] ?? 0;
                final expected = cashFloat.openingBalance +
                    cashFloat.floatReceived -
                    daily;
                final variance = cashFloat.reportedClosingBalance - expected;
                return [
                  date,
                  if (includeSite)
                    siteNames[cashFloat.siteId] ?? cashFloat.siteId,
                  CurrencyFormatter.format(cashFloat.openingBalance),
                  CurrencyFormatter.format(cashFloat.floatReceived),
                  CurrencyFormatter.format(daily),
                  CurrencyFormatter.format(expected),
                  CurrencyFormatter.format(cashFloat.reportedClosingBalance),
                  CurrencyFormatter.format(variance),
                  variance.abs() < 0.005 ? 'OK' : 'CHECK / MISMATCH',
                ];
              }).toList(),
              navy: _navy,
              iceBlue: _iceBlue,
              slateBorder: _slateBorder,
            ),
          pw.NewPage(),
          _sectionTitle('6. MANAGEMENT CHARTS', _steelBlue),
          pw.SizedBox(height: 8),
          if (chartMonthData.isEmpty && chartCategoryData.isEmpty)
            _emptyCard('No expense data available for charts.')
          else ...[
            if (chartMonthData.isNotEmpty) ...[
              pw.Text(
                'Total Spend by Month',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              pw.SizedBox(height: 6),
              _barChart(chartMonthData, _steelBlue),
              pw.SizedBox(height: 16),
            ],
            if (chartCategoryData.isNotEmpty) ...[
              pw.Text(
                'Expense Breakdown by Category',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              pw.SizedBox(height: 6),
              _pieChart(chartCategoryData, chartPalette),
              pw.SizedBox(height: 16),
            ],
            if (burnPoints.isNotEmpty) ...[
              pw.Text(
                'Cumulative Expenditure Trend',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              pw.SizedBox(height: 6),
              _lineChart(burnPoints, _steelBlue),
            ],
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildKpiGrid(List<List<String>> values) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (item) => pw.Container(
              width: 245,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: _iceBlue,
                border: pw.Border.all(color: _slateBorder),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    item[0],
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    item[1],
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  /// Generates a single daily-log "executive report" with navy/steel-blue
  /// styling, including work activities, site photographs, materials,
  /// equipment, expenses, and a cash-flow summary.
  static Future<File> generateDailyLogReport({
    required Site site,
    required DailyLog log,
    required List<Attendance> attendance,
    required List<Worker> workers,
    required List<MaterialStockLog> materials,
    required List<EquipmentDippingLog> equipment,
    required List<Expense> expenses,
    List<DieselActivityIssuance> dieselActivity = const [],
    List<Expense> monthlyExpenses = const [],
    List<ConcretePour> concretePours = const [],
    CashFloat? cashFloat,
  }) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(theme: theme);
    final navy = PdfColor.fromHex('#1A365D');
    final steelBlue = PdfColor.fromHex('#2B6CB0');
    final iceBlue = PdfColor.fromHex('#EBF8FF');
    final slateBorder = PdfColors.blueGrey200;
    final emerald = PdfColor.fromHex('#059669');
    final crimson = PdfColor.fromHex('#DC2626');
    final chartPalette = [
      steelBlue,
      PdfColor.fromHex('#38B2AC'),
      PdfColor.fromHex('#ED8936'),
      PdfColor.fromHex('#9F7AEA'),
      PdfColor.fromHex('#48BB78'),
      PdfColor.fromHex('#F56565'),
      PdfColor.fromHex('#ECC94B'),
    ];

    final totalExpenses = expenses.fold<double>(0.0, (s, e) => s + e.amount);
    final dateStr = DateFormat.yMMMd().format(log.date);
    final workText = log.workCompleted ?? '';

    // ---- Reinforcement (rebar) roll-up across all rebar sizes ----
    final rebarRows = materials
        .where((m) => m.itemName.contains('Rebar'))
        .toList();
    final rebarOpen = rebarRows.fold<double>(
      0.0,
      (s, m) => s + m.openingBalance,
    );
    final rebarRecv = rebarRows.fold<double>(0.0, (s, m) => s + m.received);
    final rebarIssue = rebarRows.fold<double>(0.0, (s, m) => s + m.issued);
    final rebarClose = rebarRows.fold<double>(
      0.0,
      (s, m) => s + m.closingBalance,
    );

    // ---- Diesel general summary: bulk tank + per-machine + activities ----
    final dieselRow = materials.where((m) => m.itemName == 'Diesel').toList();
    final dieselOpen = dieselRow.isNotEmpty
        ? dieselRow.first.openingBalance
        : 0.0;
    final dieselRecv = dieselRow.isNotEmpty ? dieselRow.first.received : 0.0;
    final dieselToMachines = equipment.fold<double>(
      0.0,
      (s, e) => s + e.dieselIssuedLitres,
    );
    final dieselToActivities = dieselActivity.fold<double>(
      0.0,
      (s, a) => s + a.litresIssued,
    );
    final dieselBalance =
        dieselOpen + dieselRecv - dieselToMachines - dieselToActivities;

    // ---- Chart data ----
    final categoryTotals = <String, double>{};
    for (final e in expenses) {
      categoryTotals[e.category.label] =
          (categoryTotals[e.category.label] ?? 0) + e.amount;
    }
    final burnSource = monthlyExpenses.isNotEmpty ? monthlyExpenses : expenses;
    final dailyTotals = <DateTime, double>{};
    for (final e in burnSource) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      dailyTotals[d] = (dailyTotals[d] ?? 0) + e.amount;
    }
    final sortedDays = dailyTotals.keys.toList()..sort();
    double cumulative = 0;
    final burnPoints = sortedDays.map((d) {
      cumulative += dailyTotals[d]!;
      return MapEntry(d, cumulative);
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildDailyHeader(
          navy,
          site.name,
          site.address ?? 'N/A',
          dateStr,
          log.id,
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _sectionTitle('1. WORK ACTIVITIES EXECUTED', steelBlue),
          pw.SizedBox(height: 8),
          if (workText.isEmpty)
            _emptyCard('No work activities recorded')
          else
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: slateBorder),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: workText.split('\n').map((line) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '• ',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Expanded(child: pw.Text(line.trim())),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          pw.NewPage(),
          _sectionTitle('2. SITE PHOTOGRAPHS', steelBlue),
          pw.SizedBox(height: 8),
          if (log.photoPaths.isEmpty)
            _emptyCard('No photos captured for this date')
          else
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: log.photoPaths.map((path) {
                final file = File(path);
                if (!file.existsSync()) return pw.SizedBox();
                return pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: slateBorder),
                  ),
                  child: pw.Image(
                    pw.MemoryImage(file.readAsBytesSync()),
                    width: 150,
                    height: 150,
                    fit: pw.BoxFit.cover,
                  ),
                );
              }).toList(),
            ),
          pw.NewPage(),
          _sectionTitle('3. MATERIAL STOCK RECONCILIATION', steelBlue),
          pw.SizedBox(height: 8),
          if (materials.isEmpty)
            _emptyCard('No material stock records')
          else
            _buildTable(
              headers: [
                'Item',
                'Unit',
                'Opening',
                'Received',
                'Issued',
                'Closing',
              ],
              rows: materials
                  .map(
                    (m) => [
                      m.itemName,
                      m.unit,
                      m.openingBalance.toStringAsFixed(1),
                      m.received.toStringAsFixed(1),
                      m.issued.toStringAsFixed(1),
                      m.closingBalance.toStringAsFixed(1),
                    ],
                  )
                  .toList(),
              navy: navy,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
            ),
          if (rebarRows.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _reconciliationStrip(
              title: 'Reinforcement Summary (All Rebar Sizes)',
              color: steelBlue,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
              stats: {
                'Opening': rebarOpen,
                'Received': rebarRecv,
                'Issued': rebarIssue,
                'Closing': rebarClose,
              },
            ),
          ],
          pw.NewPage(),
          _sectionTitle('4. EQUIPMENT DIPPING & FUEL LOG', steelBlue),
          pw.SizedBox(height: 8),
          if (equipment.isEmpty)
            _emptyCard('No equipment dipping records')
          else
            _buildTable(
              headers: [
                'Equipment',
                'Open Dip (cm)',
                'Close Dip (cm)',
                'Diesel (L)',
                'Engine Oil (L)',
              ],
              rows: equipment
                  .map(
                    (e) => [
                      e.equipmentName,
                      e.openingDipCm?.toStringAsFixed(1) ?? '-',
                      e.closingDipCm?.toStringAsFixed(1) ?? '-',
                      e.dieselIssuedLitres.toStringAsFixed(1),
                      e.engineOilIssuedLitres.toStringAsFixed(1),
                    ],
                  )
                  .toList(),
              navy: navy,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
            ),
          if (dieselRow.isNotEmpty ||
              equipment.isNotEmpty ||
              dieselActivity.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _reconciliationStrip(
              title: 'Diesel General Summary',
              color: steelBlue,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
              stats: {
                'Opening': dieselOpen,
                'Received': dieselRecv,
                'To Machines': dieselToMachines,
                'To Activities': dieselToActivities,
                'Balance': dieselBalance,
              },
              unitSuffix: 'L',
            ),
          ],
          if (dieselActivity.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Diesel Issued to Non-Dipped Activities',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 4),
            _buildTable(
              headers: ['Activity / Machine', 'Litres Issued'],
              rows: dieselActivity
                  .map(
                    (a) => [a.activityName, a.litresIssued.toStringAsFixed(1)],
                  )
                  .toList(),
              navy: navy,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
            ),
          ],
          pw.NewPage(),
          _sectionTitle('5. CONCRETE POUR & QUALITY CONTROL', steelBlue),
          pw.SizedBox(height: 8),
          if (concretePours.isEmpty)
            _emptyCard('No concrete pours recorded for this date')
          else
            _buildTable(
              headers: [
                'Element',
                'Grade',
                'Volume (m³)',
                'Slump (mm)',
                'Cubes Cast',
                'Batch Ticket No',
              ],
              rows: concretePours
                  .map(
                    (c) => [
                      c.elementName,
                      c.concreteGrade,
                      c.volumeM3.toStringAsFixed(2),
                      c.slumpMm?.toStringAsFixed(0) ?? '-',
                      '${c.cubesCast}',
                      c.batchTicketNo ?? '-',
                    ],
                  )
                  .toList(),
              navy: navy,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
            ),
          pw.NewPage(),
          _sectionTitle('6. VISUAL ANALYTICS & CHARTS', steelBlue),
          pw.SizedBox(height: 8),
          if (categoryTotals.isEmpty)
            _emptyCard('No expense data to chart for this date')
          else ...[
            pw.Text(
              'Expenditure by Category',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 6),
            _barChart(categoryTotals, steelBlue),
            pw.SizedBox(height: 16),
            pw.Text(
              'Budget Share by Category',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 6),
            _pieChart(categoryTotals, chartPalette),
          ],
          if (burnPoints.length > 1) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Daily Cumulative Burn Rate',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 6),
            _lineChart(burnPoints, steelBlue),
          ],
          pw.NewPage(),
          _sectionTitle('7. DAILY ITEMIZED EXPENSES LEDGER', steelBlue),
          pw.SizedBox(height: 8),
          if (expenses.isEmpty)
            _emptyCard('No expenses recorded')
          else
            pw.Column(
              children: [
                _buildTable(
                  headers: [
                    'S/N',
                    'Description',
                    'Category',
                    'Unit',
                    'Unit Price',
                    'Total',
                  ],
                  rows: expenses
                      .map(
                        (e) => [
                          '${e.serialNo ?? 0}',
                          e.displayDescription,
                          e.category.label,
                          e.unit ?? '-',
                          CurrencyFormatter.format(e.unitPrice ?? e.amount),
                          CurrencyFormatter.format(e.amount),
                        ],
                      )
                      .toList(),
                  navy: navy,
                  iceBlue: iceBlue,
                  slateBorder: slateBorder,
                  // S/N is fixed and narrow so it can never be squeezed out;
                  // Description gets the largest flex share so long text
                  // wraps within its own column instead of crowding S/N.
                  columnWidths: {
                    0: const pw.FixedColumnWidth(26),
                    1: const pw.FlexColumnWidth(3.2),
                    2: const pw.FlexColumnWidth(1.6),
                    3: const pw.FixedColumnWidth(40),
                    4: const pw.FlexColumnWidth(1.3),
                    5: const pw.FlexColumnWidth(1.3),
                  },
                ),
                pw.SizedBox(height: 8),
                _totalBar('SUB-TOTAL', totalExpenses, navy),
              ],
            ),
          pw.NewPage(),
          _sectionTitle('8. CASH FLOW RECONCILIATION', steelBlue),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: iceBlue,
              border: pw.Border.all(color: slateBorder),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: cashFloat != null
                ? pw.Column(
                    children: [
                      _summaryRow(
                        'Opening Balance:',
                        CurrencyFormatter.format(cashFloat.openingBalance),
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Float Received:',
                        CurrencyFormatter.format(cashFloat.floatReceived),
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Total Daily Expenses:',
                        CurrencyFormatter.format(cashFloat.totalExpenses),
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Expected Closing Balance:',
                        CurrencyFormatter.format(
                          cashFloat.expectedClosingBalance,
                        ),
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Reported Closing Balance:',
                        CurrencyFormatter.format(
                          cashFloat.reportedClosingBalance,
                        ),
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Variance:',
                        CurrencyFormatter.format(cashFloat.variance),
                        valueColor: cashFloat.variance.abs() < 0.005
                            ? emerald
                            : crimson,
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Status:',
                        cashFloat.status.label,
                        valueColor: cashFloat.status == CashFloatStatus.ok
                            ? emerald
                            : crimson,
                      ),
                      if (cashFloat.isOutOfPocketDeficit) ...[
                        pw.Divider(color: slateBorder),
                        _summaryRow(
                          'Alert:',
                          'OUT-OF-POCKET DEFICIT',
                          valueColor: crimson,
                        ),
                      ],
                    ],
                  )
                : pw.Column(
                    children: [
                      _summaryRow(
                        'Total Daily Expenses:',
                        CurrencyFormatter.format(totalExpenses),
                      ),
                      pw.Divider(color: slateBorder),
                      _summaryRow(
                        'Net Cash Position:',
                        CurrencyFormatter.format(-totalExpenses),
                        valueColor: totalExpenses > 0 ? crimson : emerald,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'No cash-float reconciliation was recorded for this date.',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
          ),
          pw.SizedBox(height: 30),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Prepared By:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Container(width: 150, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Site Supervisor Signature',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Verified By:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Container(width: 150, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Project Manager Signature',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return _saveDoc(pdf, '${site.name}_daily_${log.id.substring(0, 8)}');
  }

  static pw.Widget _buildDailyHeader(
    PdfColor navy,
    String siteName,
    String location,
    String date,
    String logId,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: navy),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SITE DAILY REPORT',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            siteName,
            style: pw.TextStyle(color: PdfColors.white, fontSize: 14),
          ),
          pw.Text(
            location,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Date: $date',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
              ),
              pw.Text(
                'Ref: SDL-${logId.substring(0, 8)}',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount} • Generated ${DateTime.now().toIso8601String()}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
      ),
    );
  }

  static pw.Widget _sectionTitle(String text, PdfColor color) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  /// A full-width colored bar with a label on the left and a currency
  /// amount on the right — used for sub-totals and grand totals.
  static pw.Widget _totalBar(String label, double amount, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            CurrencyFormatter.format(amount),
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Navy banner header shared by the site and project reports, styled to
  /// match the daily-log report instead of the old plain-text header.
  static pw.Widget _buildReportHeader(
    String kicker,
    String title,
    String? subtitle1,
    String? subtitle2,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: _navy),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            kicker,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (subtitle1 != null && subtitle1.isNotEmpty)
            pw.Text(
              subtitle1,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
            ),
          if (subtitle2 != null && subtitle2.isNotEmpty)
            pw.Text(
              subtitle2,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
            ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _emptyCard(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Text(text, style: const pw.TextStyle(color: PdfColors.grey)),
    );
  }

  static pw.Widget _buildTable({
    required List<String> headers,
    required List<List<String>> rows,
    required PdfColor navy,
    required PdfColor iceBlue,
    required PdfColor slateBorder,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: slateBorder, width: 0.5),
      columnWidths: columnWidths ?? {0: const pw.FlexColumnWidth(2)},
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: navy),
          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                h,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            );
          }).toList(),
        ),
        ...rows.asMap().entries.map((entry) {
          final isEven = entry.key % 2 == 0;
          return pw.TableRow(
            decoration: isEven ? null : pw.BoxDecoration(color: iceBlue),
            children: entry.value.map((cell) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(cell, style: const pw.TextStyle(fontSize: 10)),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  /// A horizontal strip of key/value reconciliation stats — used for the
  /// Reinforcement Summary and Diesel General Summary call-out blocks.
  static pw.Widget _reconciliationStrip({
    required String title,
    required PdfColor color,
    required PdfColor iceBlue,
    required PdfColor slateBorder,
    required Map<String, double> stats,
    String unitSuffix = '',
  }) {
    final entries = stats.entries.toList();
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: iceBlue,
        border: pw.Border.all(color: slateBorder),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: color,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: entries.map((e) {
              final isLast = e.key == entries.last.key;
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    e.key,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    '${e.value.toStringAsFixed(1)}$unitSuffix',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: isLast ? 12 : 10,
                      color: isLast ? color : PdfColors.black,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Simple horizontal bar chart — one proportional-width bar per category,
  /// no canvas needed, so it renders identically across pdf-package versions.
  static pw.Widget _barChart(Map<String, double> data, PdfColor color) {
    final maxVal = data.values.fold<double>(0, (m, v) => v > m ? v : m);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: data.entries.map((e) {
        final frac = maxVal > 0 ? (e.value / maxVal) : 0.0;
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 90,
                child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.Expanded(
                child: pw.Container(
                  height: 12,
                  color: PdfColors.grey200,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Expanded(
                        flex: (frac.clamp(0.02, 1.0) * 1000).round(),
                        child: pw.Container(color: color),
                      ),
                      pw.Expanded(
                        flex: (1000 - (frac.clamp(0.02, 1.0) * 1000).round())
                            .clamp(0, 1000),
                        child: pw.SizedBox(),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(
                width: 50,
                child: pw.Text(
                  CurrencyFormatter.format(e.value),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Pie chart drawn on a canvas (slices approximated with short line
  /// segments) plus a text legend with percentage share per category.
  static pw.Widget _pieChart(Map<String, double> data, List<PdfColor> palette) {
    final total = data.values.fold<double>(0, (s, v) => s + v);
    final entries = data.entries.toList();
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 110,
          height: 110,
          child: pw.CustomPaint(
            size: const PdfPoint(110, 110),
            painter: (canvas, size) {
              if (total <= 0) return;
              final cx = size.x / 2;
              final cy = size.y / 2;
              final r = size.x / 2 - 4;
              double startAngle = -3.14159265 / 2;
              for (var i = 0; i < entries.length; i++) {
                final value = entries[i].value;
                final sweep = (value / total) * 2 * 3.14159265;
                final color = palette[i % palette.length];
                canvas
                  ..setColor(color)
                  ..moveTo(cx, cy);
                const steps = 24;
                for (var s = 0; s <= steps; s++) {
                  final a = startAngle + sweep * (s / steps);
                  canvas.lineTo(cx + r * _cos(a), cy + r * _sin(a));
                }
                canvas
                  ..closePath()
                  ..fillPath();
                startAngle += sweep;
              }
            },
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final pct = total > 0 ? (e.value / total * 100) : 0.0;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 8,
                      height: 8,
                      color: palette[i % palette.length],
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Text(
                        '${e.key} — ${pct.toStringAsFixed(1)}%',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Cumulative daily-spend burn-rate line chart, drawn on a canvas with a
  /// simple baseline axis and connected point markers.
  static pw.Widget _lineChart(
    List<MapEntry<DateTime, double>> points,
    PdfColor color,
  ) {
    final maxVal = points.fold<double>(0, (m, e) => e.value > m ? e.value : m);
    final dateFmt = DateFormat.Md();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: double.infinity,
          height: 100,
          child: pw.CustomPaint(
            size: const PdfPoint(480, 100),
            painter: (canvas, size) {
              const padding = 8.0;
              final plotW = size.x - padding * 2;
              final plotH = size.y - padding * 2;
              // Baseline axis
              canvas
                ..setColor(PdfColors.grey400)
                ..setLineWidth(0.5)
                ..moveTo(padding, size.y - padding)
                ..lineTo(size.x - padding, size.y - padding)
                ..strokePath();
              if (points.isEmpty || maxVal <= 0) return;
              final stepX = points.length > 1
                  ? plotW / (points.length - 1)
                  : 0.0;
              canvas
                ..setColor(color)
                ..setLineWidth(1.2);
              for (var i = 0; i < points.length; i++) {
                final x = padding + stepX * i;
                final y = size.y - padding - (points[i].value / maxVal) * plotH;
                if (i == 0) {
                  canvas.moveTo(x, y);
                } else {
                  canvas.lineTo(x, y);
                }
              }
              canvas.strokePath();
              for (var i = 0; i < points.length; i++) {
                final x = padding + stepX * i;
                final y = size.y - padding - (points[i].value / maxVal) * plotH;
                canvas
                  ..setColor(color)
                  ..drawEllipse(x, y, 1.6, 1.6)
                  ..fillPath();
              }
            },
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              dateFmt.format(points.first.key),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              'Cumulative spend',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              dateFmt.format(points.last.key),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  static double _cos(double radians) => math.cos(radians);
  static double _sin(double radians) => math.sin(radians);

  static pw.Widget _summaryRow(
    String label,
    String value, {
    PdfColor? valueColor,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  static pw.Widget _logBlock(DailyLog log, DateFormat dateFmt) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            dateFmt.format(log.date),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (log.weather != null) pw.Text('Weather: ${log.weather}'),
          if (log.crewCount != null) pw.Text('Crew: ${log.crewCount}'),
          if (log.workCompleted != null)
            pw.Text('Work completed: ${log.workCompleted}'),
          if (log.issues != null) pw.Text('Issues: ${log.issues}'),
          if (log.photoPaths.isNotEmpty)
            pw.Wrap(
              spacing: 6,
              runSpacing: 6,
              children: log.photoPaths.map((path) {
                final file = File(path);
                if (!file.existsSync()) return pw.SizedBox();
                return pw.Image(
                  pw.MemoryImage(file.readAsBytesSync()),
                  width: 100,
                  height: 100,
                  fit: pw.BoxFit.cover,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  static Future<File> _saveDoc(pw.Document doc, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    await reportsDir.create(recursive: true);
    final safeName = baseName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(reportsDir.path, '${safeName}_$timestamp.pdf'));
    await file.writeAsBytes(await doc.save());
    return file;
  }
}
