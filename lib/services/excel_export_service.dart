import 'dart:io';

import 'package:excel_community/excel_community.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/cash_float.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../models/project.dart';
import '../models/site.dart';
import 'reconciliation_service.dart';

/// Creates the six-tab audit workbook defined by the field reporting spec.
/// Summary sheets contain live Excel formulas; the Charts sheet contains
/// native OOXML charts and hard-value source tables so charts render at once.
class ExcelExportService {
  static final _navy = ExcelColor.fromHexString('153A5B');
  static final _paleBlue = ExcelColor.fromHexString('DCE6F1');
  static final _green = ExcelColor.fromHexString('E2F0D9');
  static final _red = ExcelColor.fromHexString('FCE4D6');
  static const _currencyFormat = CustomNumericNumFormat(
    formatCode: '"₦"#,##0.00;[Red]-"₦"#,##0.00',
  );
  static const _percentFormat = CustomNumericNumFormat(formatCode: '0.00%');

  static Future<File> generateSiteWorkbook({
    required Project project,
    required Site site,
    required List<DailyLog> logs,
    required List<MaterialItem> materials,
    required List<Expense> expenses,
  }) async {
    final floats = await DatabaseHelper.instance.getCashFloatsForSite(site.id);
    return _generate(
      project: project,
      sites: [site],
      expensesBySite: {site.id: expenses},
      cashFloatsBySite: {site.id: floats},
      fileStem: '${site.name}_Site_Database',
    );
  }

  static Future<File> generateProjectWorkbook({
    required Project project,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required Map<String, List<MaterialItem>> materialsBySite,
    required Map<String, List<Expense>> expensesBySite,
  }) async {
    final cashFloatsBySite = <String, List<CashFloat>>{};
    for (final site in sites) {
      cashFloatsBySite[site.id] = await DatabaseHelper.instance
          .getCashFloatsForSite(site.id);
    }
    return _generate(
      project: project,
      sites: sites,
      expensesBySite: expensesBySite,
      cashFloatsBySite: cashFloatsBySite,
      fileStem: '${project.name}_Project_Database',
    );
  }

  static Future<File> _generate({
    required Project project,
    required List<Site> sites,
    required Map<String, List<Expense>> expensesBySite,
    required Map<String, List<CashFloat>> cashFloatsBySite,
    required String fileStem,
  }) async {
    final siteNames = {for (final site in sites) site.id: site.name};
    final expenses = <_SiteExpense>[
      for (final site in sites)
        for (final expense in expensesBySite[site.id] ?? const <Expense>[])
          _SiteExpense(siteNames[site.id] ?? site.id, expense),
    ]..sort((a, b) => a.expense.date.compareTo(b.expense.date));
    final floats = <_SiteCashFloat>[
      for (final site in sites)
        for (final cashFloat
            in cashFloatsBySite[site.id] ?? const <CashFloat>[])
          _SiteCashFloat(siteNames[site.id] ?? site.id, cashFloat),
    ]..sort((a, b) => a.cashFloat.date.compareTo(b.cashFloat.date));

    final months =
        expenses.map((item) => item.expense.monthKey).toSet().toList()..sort();
    final categoryTotals = <ExpenseCategory, double>{
      for (final category in ExpenseCategory.values) category: 0,
    };
    final monthTotals = <String, double>{for (final month in months) month: 0};
    final monthCategoryTotals = <String, Map<ExpenseCategory, double>>{
      for (final month in months)
        month: {for (final category in ExpenseCategory.values) category: 0},
    };
    for (final item in expenses) {
      final expense = item.expense;
      categoryTotals[expense.category] =
          categoryTotals[expense.category]! + expense.amount;
      monthTotals[expense.monthKey] =
          (monthTotals[expense.monthKey] ?? 0) + expense.amount;
      monthCategoryTotals[expense.monthKey]![expense.category] =
          monthCategoryTotals[expense.monthKey]![expense.category]! +
          expense.amount;
    }

    final excel = Excel.createExcel();
    _buildInstructions(excel, project, sites);
    _buildDailyLog(excel, expenses, includeSite: sites.length > 1);
    _buildMonthlySummary(excel, expenses, months, monthCategoryTotals);
    _buildOverallSummary(excel, expenses, categoryTotals, floats);
    _buildCashFlow(excel, expenses, floats, includeSite: sites.length > 1);
    _buildCharts(
      excel,
      months,
      monthTotals,
      categoryTotals,
      monthCategoryTotals,
    );

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    excel.setDefaultSheet('Instructions');
    return _save(excel, fileStem);
  }

  static void _buildInstructions(
    Excel excel,
    Project project,
    List<Site> sites,
  ) {
    final sheet = excel['Instructions'];
    _title(sheet, 'CONSTRUCTION SITE EXPENSE & FLOAT AUDIT WORKBOOK', 6);
    _set(sheet, 0, 2, TextCellValue('Project'));
    _set(sheet, 1, 2, TextCellValue(project.name));
    _set(sheet, 0, 3, TextCellValue('Client'));
    _set(sheet, 1, 3, TextCellValue(project.client ?? 'Not recorded'));
    _set(sheet, 0, 4, TextCellValue('Site(s)'));
    _set(sheet, 1, 4, TextCellValue(sites.map((site) => site.name).join(', ')));
    _set(sheet, 0, 5, TextCellValue('Generated'));
    _set(
      sheet,
      1,
      5,
      TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
    );

    _headerRow(sheet, 7, const ['Operating guideline', 'Audit note']);
    const guidance = <List<String>>[
      [
        'Offline-first records',
        'The mobile SQLite database remains the system of record. Export a fresh workbook after field edits.',
      ],
      [
        'Line-item arithmetic',
        'Every total is Quantity × Unit Price. Use Quantity = 1 for a lump-sum expense.',
      ],
      [
        'Float reconciliation',
        'Expected Closing = Opening Balance + Float Received − Total Daily Expenses.',
      ],
      [
        'Variance status',
        'Variance = Reported Closing − Expected Closing. Only exactly ₦0.00 is OK; every other value is CHECK / MISMATCH.',
      ],
      [
        'Negative expected balance',
        'A negative expected closing balance is a Site Supervisor Deficit / Out-of-pocket Advance pending a later top-up.',
      ],
      [
        'Formula cells',
        'Monthly Summary, Overall Summary and Cash Flow formulas recalculate when opened in Excel or a compatible spreadsheet app.',
      ],
      [
        'Record integrity',
        'Do not overwrite the Daily Log data sheet. Make corrections in the mobile app and export again to preserve the audit trail.',
      ],
    ];
    for (var index = 0; index < guidance.length; index++) {
      _set(sheet, 0, index + 8, TextCellValue(guidance[index][0]));
      _set(sheet, 1, index + 8, TextCellValue(guidance[index][1]));
      _styleRow(sheet, index + 8, 2, _bodyStyle(wrap: true));
      sheet.setRowHeight(index + 8, 42);
    }
    sheet.setColumnWidth(0, 28);
    sheet.setColumnWidth(1, 86);
    for (var column = 2; column < 6; column++) {
      sheet.setColumnWidth(column, 4);
    }
    _styleRange(sheet, 0, 2, 0, 5, _labelStyle());
    _styleRange(sheet, 1, 2, 1, 5, _bodyStyle(wrap: true));
  }

  static void _buildDailyLog(
    Excel excel,
    List<_SiteExpense> expenses, {
    required bool includeSite,
  }) {
    final sheet = excel['Daily Log'];
    final headers = [
      'Date',
      'S/N',
      'Description',
      'Unit',
      'Quantity',
      'Unit Price',
      'Total Amount',
      'Category',
      'Month',
      if (includeSite) 'Site',
    ];
    _headerRow(sheet, 0, headers);
    for (var index = 0; index < expenses.length; index++) {
      final item = expenses[index];
      final expense = item.expense;
      final row = index + 1;
      final values = <CellValue?>[
        TextCellValue(DateFormat('yyyy-MM-dd').format(expense.date)),
        expense.serialNo == null
            ? TextCellValue('')
            : IntCellValue(expense.serialNo!),
        TextCellValue(expense.displayDescription),
        TextCellValue(expense.unit ?? '1'),
        DoubleCellValue(expense.quantity),
        DoubleCellValue(expense.unitPrice ?? expense.amount),
        DoubleCellValue(expense.amount),
        TextCellValue(expense.category.label),
        TextCellValue(expense.monthKey),
        if (includeSite) TextCellValue(item.siteName),
      ];
      for (var column = 0; column < values.length; column++) {
        _set(sheet, column, row, values[column]);
      }
      _styleRow(sheet, row, values.length, _bodyStyle());
      _currencyCell(sheet, 5, row);
      _currencyCell(sheet, 6, row);
    }
    sheet.frozenRows = 1;
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 8);
    sheet.setColumnWidth(2, 42);
    sheet.setColumnWidth(3, 13);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 16);
    sheet.setColumnWidth(6, 17);
    sheet.setColumnWidth(7, 34);
    sheet.setColumnWidth(8, 12);
    if (includeSite) sheet.setColumnWidth(9, 24);
  }

  static void _buildMonthlySummary(
    Excel excel,
    List<_SiteExpense> expenses,
    List<String> months,
    Map<String, Map<ExpenseCategory, double>> cached,
  ) {
    final sheet = excel['Monthly Summary'];
    final headers = ['Category', ...months, 'Category Total'];
    _headerRow(sheet, 0, headers);
    final dataEnd = expenses.isEmpty ? 2 : expenses.length + 1;
    for (
      var categoryIndex = 0;
      categoryIndex < ExpenseCategory.values.length;
      categoryIndex++
    ) {
      final category = ExpenseCategory.values[categoryIndex];
      final row = categoryIndex + 1;
      final excelRow = row + 1;
      _set(sheet, 0, row, TextCellValue(category.label));
      _styleRow(sheet, row, headers.length, _bodyStyle());
      for (var monthIndex = 0; monthIndex < months.length; monthIndex++) {
        final column = monthIndex + 1;
        final monthHeader = '${_columnName(column)}\$1';
        final formula =
            'SUMIFS(\'Daily Log\'!\$G\$2:\$G\$$dataEnd,\'Daily Log\'!\$H\$2:\$H\$$dataEnd,\$A$excelRow,\'Daily Log\'!\$I\$2:\$I\$$dataEnd,$monthHeader)';
        _set(
          sheet,
          column,
          row,
          FormulaCellValue(
            formula,
            cachedValue: DoubleCellValue(
              cached[months[monthIndex]]?[category] ?? 0,
            ),
          ),
        );
        _currencyCell(sheet, column, row);
      }
      final totalColumn = months.length + 1;
      final firstMonthColumn = _columnName(1);
      final lastMonthColumn = _columnName(months.isEmpty ? 1 : months.length);
      final cachedTotal = months.fold<double>(
        0,
        (sum, month) => sum + (cached[month]?[category] ?? 0),
      );
      final formula = months.isEmpty
          ? 'SUMIF(\'Daily Log\'!\$H\$2:\$H\$$dataEnd,\$A$excelRow,\'Daily Log\'!\$G\$2:\$G\$$dataEnd)'
          : 'SUM($firstMonthColumn$excelRow:$lastMonthColumn$excelRow)';
      _set(
        sheet,
        totalColumn,
        row,
        FormulaCellValue(formula, cachedValue: DoubleCellValue(cachedTotal)),
      );
      _currencyCell(sheet, totalColumn, row);
    }
    final totalRow = ExpenseCategory.values.length + 1;
    _set(sheet, 0, totalRow, TextCellValue('MONTHLY TOTAL'));
    _styleRow(sheet, totalRow, headers.length, _totalStyle());
    for (var column = 1; column < headers.length; column++) {
      final letter = _columnName(column);
      final cachedTotal = column <= months.length
          ? cached[months[column - 1]]!.values.fold<double>(
              0,
              (sum, value) => sum + value,
            )
          : cached.values.fold<double>(
              0,
              (sum, row) => sum + row.values.fold<double>(0, (a, b) => a + b),
            );
      _set(
        sheet,
        column,
        totalRow,
        FormulaCellValue(
          'SUM(${letter}2:${letter}${ExpenseCategory.values.length + 1})',
          cachedValue: DoubleCellValue(cachedTotal),
        ),
      );
      _currencyCell(sheet, column, totalRow, total: true);
    }
    sheet.frozenRows = 1;
    sheet.frozenColumns = 1;
    sheet.setColumnWidth(0, 36);
    for (var column = 1; column < headers.length; column++) {
      sheet.setColumnWidth(column, 17);
    }
  }

  static void _buildOverallSummary(
    Excel excel,
    List<_SiteExpense> expenses,
    Map<ExpenseCategory, double> categoryTotals,
    List<_SiteCashFloat> floats,
  ) {
    final sheet = excel['Overall Summary'];
    _headerRow(sheet, 0, const [
      'Category',
      'Total Spend',
      'Item Count',
      '% of Total',
    ]);
    final dataEnd = expenses.isEmpty ? 2 : expenses.length + 1;
    final grandTotal = categoryTotals.values.fold<double>(0, (a, b) => a + b);
    for (var index = 0; index < ExpenseCategory.values.length; index++) {
      final category = ExpenseCategory.values[index];
      final row = index + 1;
      final excelRow = row + 1;
      final cachedSpend = categoryTotals[category] ?? 0;
      final cachedCount = expenses
          .where((item) => item.expense.category == category)
          .length;
      _set(sheet, 0, row, TextCellValue(category.label));
      _set(
        sheet,
        1,
        row,
        FormulaCellValue(
          'SUMIF(\'Daily Log\'!\$H\$2:\$H\$$dataEnd,\$A$excelRow,\'Daily Log\'!\$G\$2:\$G\$$dataEnd)',
          cachedValue: DoubleCellValue(cachedSpend),
        ),
      );
      _set(
        sheet,
        2,
        row,
        FormulaCellValue(
          'COUNTIF(\'Daily Log\'!\$H\$2:\$H\$$dataEnd,\$A$excelRow)',
          cachedValue: IntCellValue(cachedCount),
        ),
      );
      _set(
        sheet,
        3,
        row,
        FormulaCellValue(
          'IF(\$B\$12=0,0,B$excelRow/\$B\$12)',
          cachedValue: DoubleCellValue(
            grandTotal == 0 ? 0 : cachedSpend / grandTotal,
          ),
        ),
      );
      _styleRow(sheet, row, 4, _bodyStyle());
      _currencyCell(sheet, 1, row);
      _percentCell(sheet, 3, row);
    }
    const totalRow = 11;
    _set(sheet, 0, totalRow, TextCellValue('TOTAL'));
    _set(
      sheet,
      1,
      totalRow,
      FormulaCellValue('SUM(B2:B11)', cachedValue: DoubleCellValue(grandTotal)),
    );
    _set(
      sheet,
      2,
      totalRow,
      FormulaCellValue(
        'SUM(C2:C11)',
        cachedValue: IntCellValue(expenses.length),
      ),
    );
    _set(
      sheet,
      3,
      totalRow,
      FormulaCellValue(
        'IF(B12=0,0,SUM(D2:D11))',
        cachedValue: DoubleCellValue(grandTotal == 0 ? 0 : 1),
      ),
    );
    _styleRow(sheet, totalRow, 4, _totalStyle());
    _currencyCell(sheet, 1, totalRow, total: true);
    _percentCell(sheet, 3, totalRow, total: true);

    _headerRow(sheet, 14, const ['Key KPI', 'Value']);
    final totalFloat = floats.fold<double>(
      0,
      (sum, item) => sum + item.cashFloat.floatReceived,
    );
    final latestBalanceBySite = <String, double>{};
    for (final item in floats) {
      latestBalanceBySite[item.siteName] =
          item.cashFloat.expectedClosingBalance;
    }
    final latestBalance = floats.isEmpty
        ? totalFloat - grandTotal
        : latestBalanceBySite.values.fold<double>(
            0,
            (sum, value) => sum + value,
          );
    final cashFlowEnd = floats.length + 1;
    final currentBalanceFormula = floats.isEmpty
        ? 'B17-B16'
        : latestBalanceBySite.length == 1
        ? "LOOKUP(2,1/('Cash Flow'!E2:E$cashFlowEnd<>\"\"),'Cash Flow'!E2:E$cashFlowEnd)"
        : "SUM(XLOOKUP(UNIQUE(FILTER('Cash Flow'!J2:J$cashFlowEnd,'Cash Flow'!J2:J$cashFlowEnd<>\"\")),'Cash Flow'!J2:J$cashFlowEnd,'Cash Flow'!E2:E$cashFlowEnd,0,0,-1))";
    final activeDates = expenses
        .map((item) => DateFormat('yyyy-MM-dd').format(item.expense.date))
        .toSet()
        .length;
    ExpenseCategory? highestCategory;
    double highestTotal = -1;
    for (final entry in categoryTotals.entries) {
      if (entry.value > highestTotal) {
        highestCategory = entry.key;
        highestTotal = entry.value;
      }
    }
    final kpis = <_KpiFormula>[
      _KpiFormula('Total Site Spend', 'B12', grandTotal, currency: true),
      _KpiFormula(
        'Total Float Received',
        "SUM('Cash Flow'!B2:B${floats.isEmpty ? 2 : floats.length + 1})",
        totalFloat,
        currency: true,
      ),
      _KpiFormula(
        'Current Cash Balance',
        currentBalanceFormula,
        latestBalance,
        currency: true,
      ),
      _KpiFormula(
        'Highest Cost Category',
        'IF(B12=0,\"No spend yet\",INDEX(A2:A11,MATCH(MAX(B2:B11),B2:B11,0)))',
        grandTotal == 0
            ? 'No spend yet'
            : highestCategory?.label ?? 'No spend yet',
      ),
      _KpiFormula(
        'Highest Category %',
        'INDEX(D2:D11,MATCH(MAX(B2:B11),B2:B11,0))',
        grandTotal == 0 ? 0 : highestTotal / grandTotal,
        percent: true,
      ),
      _KpiFormula(
        'Average Daily Spend',
        activeDates == 0 ? '0' : 'B12/$activeDates',
        activeDates == 0 ? 0 : grandTotal / activeDates,
        currency: true,
      ),
    ];
    for (var index = 0; index < kpis.length; index++) {
      final row = 15 + index;
      final kpi = kpis[index];
      _set(sheet, 0, row, TextCellValue(kpi.label));
      _set(
        sheet,
        1,
        row,
        FormulaCellValue(kpi.formula, cachedValue: _cellValue(kpi.cached)),
      );
      _styleRow(sheet, row, 2, _bodyStyle());
      if (kpi.currency) _currencyCell(sheet, 1, row);
      if (kpi.percent) _percentCell(sheet, 1, row);
    }
    sheet.frozenRows = 1;
    sheet.setColumnWidth(0, 38);
    sheet.setColumnWidth(1, 22);
    sheet.setColumnWidth(2, 15);
    sheet.setColumnWidth(3, 15);
  }

  static void _buildCashFlow(
    Excel excel,
    List<_SiteExpense> expenses,
    List<_SiteCashFloat> floats, {
    required bool includeSite,
  }) {
    final sheet = excel['Cash Flow'];
    final headers = [
      'Date',
      'Float Top-up',
      'Daily Expenses',
      'Reported Closing',
      'Expected Closing',
      'Variance',
      'Audit Status',
      'Opening Balance',
      'Notes',
      if (includeSite) 'Site',
    ];
    _headerRow(sheet, 0, headers);
    final dailyEnd = expenses.isEmpty ? 2 : expenses.length + 1;
    for (var index = 0; index < floats.length; index++) {
      final item = floats[index];
      final cashFloat = item.cashFloat;
      final row = index + 1;
      final excelRow = row + 1;
      final date = DateFormat('yyyy-MM-dd').format(cashFloat.date);
      final actualDailyExpense = expenses
          .where(
            (itemExpense) =>
                itemExpense.expense.siteId == cashFloat.siteId &&
                DateFormat('yyyy-MM-dd').format(itemExpense.expense.date) ==
                    date,
          )
          .fold<double>(
            0,
            (sum, itemExpense) => sum + itemExpense.expense.amount,
          );
      final result = ReconciliationService.reconcile(
        openingBalance: cashFloat.openingBalance,
        floatReceived: cashFloat.floatReceived,
        lineItemTotals: [actualDailyExpense],
        reportedClosingBalance: cashFloat.reportedClosingBalance,
      );
      _set(sheet, 0, row, TextCellValue(date));
      _set(sheet, 1, row, DoubleCellValue(cashFloat.floatReceived));
      _set(
        sheet,
        2,
        row,
        FormulaCellValue(
          'SUMIFS(\'Daily Log\'!\$G\$2:\$G\$$dailyEnd,\'Daily Log\'!\$A\$2:\$A\$$dailyEnd,A$excelRow${includeSite ? ",\'Daily Log\'!\$J\$2:\$J\$$dailyEnd,J$excelRow" : ''})',
          cachedValue: DoubleCellValue(actualDailyExpense),
        ),
      );
      _set(sheet, 3, row, DoubleCellValue(cashFloat.reportedClosingBalance));
      _set(
        sheet,
        4,
        row,
        FormulaCellValue(
          'H$excelRow+B$excelRow-C$excelRow',
          cachedValue: DoubleCellValue(result.expectedClosingBalance),
        ),
      );
      _set(
        sheet,
        5,
        row,
        FormulaCellValue(
          'D$excelRow-E$excelRow',
          cachedValue: DoubleCellValue(result.variance),
        ),
      );
      _set(
        sheet,
        6,
        row,
        FormulaCellValue(
          'IF(ROUND(F$excelRow,2)=0,\"OK\",\"CHECK / MISMATCH\")',
          cachedValue: TextCellValue(result.statusLabel),
        ),
      );
      _set(sheet, 7, row, DoubleCellValue(cashFloat.openingBalance));
      _set(sheet, 8, row, TextCellValue(cashFloat.notes ?? ''));
      if (includeSite) _set(sheet, 9, row, TextCellValue(item.siteName));
      _styleRow(sheet, row, headers.length, _bodyStyle());
      for (final column in [1, 2, 3, 4, 5, 7]) {
        _currencyCell(sheet, column, row);
      }
      _cell(sheet, 6, row).cellStyle = result.status == CashFloatStatus.ok
          ? _statusStyle(ok: true)
          : _statusStyle(ok: false);
      if (result.isOutOfPocketDeficit) {
        _cell(sheet, 4, row).cellStyle = _deficitCurrencyStyle();
      }
    }
    sheet.frozenRows = 1;
    final widths = [
      14.0,
      17.0,
      17.0,
      19.0,
      19.0,
      16.0,
      22.0,
      18.0,
      40.0,
      if (includeSite) 24.0,
    ];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }
  }

  static void _buildCharts(
    Excel excel,
    List<String> months,
    Map<String, double> monthTotals,
    Map<ExpenseCategory, double> categoryTotals,
    Map<String, Map<ExpenseCategory, double>> monthCategoryTotals,
  ) {
    final sheet = excel['Charts'];
    const monthlyColumn = 30;
    const categoryColumn = 33;
    const trendColumn = 36;
    final chartMonths = months.isEmpty ? ['No data'] : months;
    _set(sheet, monthlyColumn, 0, TextCellValue('Month'));
    _set(sheet, monthlyColumn + 1, 0, TextCellValue('Total Spend'));
    for (var index = 0; index < chartMonths.length; index++) {
      final month = chartMonths[index];
      _set(sheet, monthlyColumn, index + 1, TextCellValue(month));
      _set(
        sheet,
        monthlyColumn + 1,
        index + 1,
        DoubleCellValue(monthTotals[month] ?? 0),
      );
    }

    _set(sheet, categoryColumn, 0, TextCellValue('Category'));
    _set(sheet, categoryColumn + 1, 0, TextCellValue('Total Spend'));
    for (var index = 0; index < ExpenseCategory.values.length; index++) {
      final category = ExpenseCategory.values[index];
      _set(sheet, categoryColumn, index + 1, TextCellValue(category.label));
      _set(
        sheet,
        categoryColumn + 1,
        index + 1,
        DoubleCellValue(categoryTotals[category] ?? 0),
      );
    }

    final trendCategories = ExpenseCategory.values
        .where((category) => (categoryTotals[category] ?? 0) > 0)
        .toList();
    if (trendCategories.isEmpty) trendCategories.add(ExpenseCategory.other);
    _set(sheet, trendColumn, 0, TextCellValue('Month'));
    for (
      var categoryIndex = 0;
      categoryIndex < trendCategories.length;
      categoryIndex++
    ) {
      _set(
        sheet,
        trendColumn + categoryIndex + 1,
        0,
        TextCellValue(trendCategories[categoryIndex].label),
      );
    }
    for (var monthIndex = 0; monthIndex < chartMonths.length; monthIndex++) {
      final month = chartMonths[monthIndex];
      _set(sheet, trendColumn, monthIndex + 1, TextCellValue(month));
      for (
        var categoryIndex = 0;
        categoryIndex < trendCategories.length;
        categoryIndex++
      ) {
        _set(
          sheet,
          trendColumn + categoryIndex + 1,
          monthIndex + 1,
          DoubleCellValue(
            monthCategoryTotals[month]?[trendCategories[categoryIndex]] ?? 0,
          ),
        );
      }
    }

    final monthEnd = chartMonths.length + 1;
    final monthCategoryRange =
        "Charts!\$${_columnName(monthlyColumn)}\$2:\$${_columnName(monthlyColumn)}\$$monthEnd";
    final monthValueRange =
        "Charts!\$${_columnName(monthlyColumn + 1)}\$2:\$${_columnName(monthlyColumn + 1)}\$$monthEnd";
    sheet.addChart(
      ColumnChart(
        title: 'Total Spend by Month',
        series: [
          ChartSeries(
            name: 'Monthly Spend',
            categoriesRange: monthCategoryRange,
            valuesRange: monthValueRange,
          ),
        ],
        anchor: ChartAnchor.at(column: 0, row: 0, width: 12, height: 16),
        showLegend: false,
      ),
    );

    final categoryEnd = ExpenseCategory.values.length + 1;
    sheet.addChart(
      DoughnutChart(
        title: 'Expense Breakdown by Category',
        series: [
          ChartSeries(
            name: 'Category Spend',
            categoriesRange:
                "Charts!\$${_columnName(categoryColumn)}\$2:\$${_columnName(categoryColumn)}\$$categoryEnd",
            valuesRange:
                "Charts!\$${_columnName(categoryColumn + 1)}\$2:\$${_columnName(categoryColumn + 1)}\$$categoryEnd",
          ),
        ],
        anchor: ChartAnchor.at(column: 12, row: 0, width: 12, height: 16),
        showLegend: true,
      ),
    );

    final trendSeries = <ChartSeries>[
      for (var index = 0; index < trendCategories.length; index++)
        ChartSeries(
          name: trendCategories[index].label,
          categoriesRange:
              "Charts!\$${_columnName(trendColumn)}\$2:\$${_columnName(trendColumn)}\$$monthEnd",
          valuesRange:
              "Charts!\$${_columnName(trendColumn + index + 1)}\$2:\$${_columnName(trendColumn + index + 1)}\$$monthEnd",
        ),
    ];
    sheet.addChart(
      LineChart(
        title: 'Monthly Category Spend Trends',
        series: trendSeries,
        anchor: ChartAnchor.at(column: 0, row: 17, width: 24, height: 18),
        showLegend: true,
      ),
    );

    for (
      var column = monthlyColumn;
      column <= trendColumn + trendCategories.length;
      column++
    ) {
      sheet.setColumnHidden(column, true);
    }
    for (var column = 0; column < 24; column++) {
      sheet.setColumnWidth(column, 9);
    }
  }

  static Future<File> _save(Excel excel, String fileStem) async {
    final bytes = excel.encode();
    if (bytes == null) throw StateError('Workbook encoding returned no data.');
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(p.join(directory.path, 'exports'));
    await exportDirectory.create(recursive: true);
    final safeName = fileStem.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(
      p.join(
        exportDirectory.path,
        '${safeName}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static void _title(Sheet sheet, String text, int lastColumn) {
    _set(sheet, 0, 0, TextCellValue(text));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: lastColumn, rowIndex: 0),
    );
    _styleRange(sheet, 0, 0, lastColumn, 0, _titleStyle());
    sheet.setRowHeight(0, 30);
  }

  static void _headerRow(Sheet sheet, int row, List<String> headers) {
    for (var column = 0; column < headers.length; column++) {
      _set(sheet, column, row, TextCellValue(headers[column]));
    }
    _styleRow(sheet, row, headers.length, _headerStyle());
    sheet.setRowHeight(row, 28);
  }

  static void _set(Sheet sheet, int column, int row, CellValue? value) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
      value,
    );
  }

  static Data _cell(Sheet sheet, int column, int row) => sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
  );

  static void _styleRow(
    Sheet sheet,
    int row,
    int columnCount,
    CellStyle style,
  ) {
    for (var column = 0; column < columnCount; column++) {
      _cell(sheet, column, row).cellStyle = style;
    }
  }

  static void _styleRange(
    Sheet sheet,
    int startColumn,
    int startRow,
    int endColumn,
    int endRow,
    CellStyle style,
  ) {
    for (var row = startRow; row <= endRow; row++) {
      for (var column = startColumn; column <= endColumn; column++) {
        _cell(sheet, column, row).cellStyle = style;
      }
    }
  }

  static void _currencyCell(
    Sheet sheet,
    int column,
    int row, {
    bool total = false,
  }) {
    _cell(sheet, column, row).cellStyle = CellStyle(
      numberFormat: _currencyFormat,
      bold: total,
      backgroundColorHex: total ? _paleBlue : ExcelColor.none,
    );
  }

  static void _percentCell(
    Sheet sheet,
    int column,
    int row, {
    bool total = false,
  }) {
    _cell(sheet, column, row).cellStyle = CellStyle(
      numberFormat: _percentFormat,
      bold: total,
      backgroundColorHex: total ? _paleBlue : ExcelColor.none,
    );
  }

  static CellStyle _titleStyle() => CellStyle(
    backgroundColorHex: _navy,
    fontColorHex: ExcelColor.white,
    bold: true,
    fontSize: 16,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  static CellStyle _headerStyle() => CellStyle(
    backgroundColorHex: _navy,
    fontColorHex: ExcelColor.white,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );

  static CellStyle _bodyStyle({bool wrap = false}) => CellStyle(
    verticalAlign: VerticalAlign.Center,
    textWrapping: wrap ? TextWrapping.WrapText : null,
  );

  static CellStyle _labelStyle() => CellStyle(
    backgroundColorHex: _paleBlue,
    bold: true,
    verticalAlign: VerticalAlign.Center,
  );

  static CellStyle _totalStyle() =>
      CellStyle(backgroundColorHex: _paleBlue, bold: true);

  static CellStyle _statusStyle({required bool ok}) => CellStyle(
    backgroundColorHex: ok ? _green : _red,
    fontColorHex: ok
        ? ExcelColor.fromHexString('006100')
        : ExcelColor.fromHexString('9C0006'),
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
  );

  static CellStyle _deficitCurrencyStyle() => CellStyle(
    backgroundColorHex: _red,
    fontColorHex: ExcelColor.fromHexString('9C0006'),
    bold: true,
    numberFormat: _currencyFormat,
  );

  static CellValue _cellValue(Object value) {
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue('$value');
  }

  static String _columnName(int zeroBasedColumn) {
    var value = zeroBasedColumn + 1;
    var result = '';
    while (value > 0) {
      value--;
      result = String.fromCharCode(65 + (value % 26)) + result;
      value ~/= 26;
    }
    return result;
  }
}

class _SiteExpense {
  final String siteName;
  final Expense expense;

  const _SiteExpense(this.siteName, this.expense);
}

class _SiteCashFloat {
  final String siteName;
  final CashFloat cashFloat;

  const _SiteCashFloat(this.siteName, this.cashFloat);
}

class _KpiFormula {
  final String label;
  final String formula;
  final Object cached;
  final bool currency;
  final bool percent;

  const _KpiFormula(
    this.label,
    this.formula,
    this.cached, {
    this.currency = false,
    this.percent = false,
  });
}
