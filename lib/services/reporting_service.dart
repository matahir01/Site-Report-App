import '../db/database_helper.dart';
import '../models/expense.dart';
import '../models/reporting_models.dart';
import 'reconciliation_service.dart';

class ReportingService {
  ReportingService._();

  static Future<DashboardSnapshot> dashboard(String siteId) async {
    final db = DatabaseHelper.instance;
    final expenses = await db.getExpensesForSite(siteId);
    final floats = await db.getCashFloatsForSite(siteId);

    final categoryTotals = <ExpenseCategory, double>{};
    final monthlyTotals = <String, double>{};
    final monthlyCategoryTotals = <String, Map<ExpenseCategory, double>>{};
    final expenseDates = <String>{};
    for (final expense in expenses) {
      categoryTotals.update(
        expense.category,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
      monthlyTotals.update(
        expense.monthKey,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
      monthlyCategoryTotals
          .putIfAbsent(expense.monthKey, () => <ExpenseCategory, double>{})
          .update(
            expense.category,
            (value) => value + expense.amount,
            ifAbsent: () => expense.amount,
          );
      expenseDates.add(expense.date.toIso8601String().substring(0, 10));
    }
    final sortedMonths = monthlyTotals.keys.toList()..sort();
    final orderedMonthlyTotals = <String, double>{
      for (final month in sortedMonths)
        month: ReconciliationService.money(monthlyTotals[month]!),
    };
    final orderedMonthlyCategories = <String, Map<ExpenseCategory, double>>{
      for (final month in sortedMonths) month: monthlyCategoryTotals[month]!,
    };
    final totalSpend = ReconciliationService.money(
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount),
    );
    final totalFloatReceived = ReconciliationService.money(
      floats.fold<double>(0, (sum, item) => sum + item.floatReceived),
    );
    ExpenseCategory? highestCategory;
    double highestTotal = 0;
    for (final entry in categoryTotals.entries) {
      if (entry.value > highestTotal) {
        highestCategory = entry.key;
        highestTotal = entry.value;
      }
    }
    return DashboardSnapshot(
      totalSpend: totalSpend,
      totalFloatReceived: totalFloatReceived,
      currentCashBalance: floats.isEmpty
          ? ReconciliationService.money(totalFloatReceived - totalSpend)
          : floats.first.expectedClosingBalance,
      highestCostCategory: highestCategory,
      highestCostCategoryPercentage: totalSpend == 0
          ? 0
          : highestTotal / totalSpend * 100,
      averageDailySpend: expenseDates.isEmpty
          ? 0
          : ReconciliationService.money(totalSpend / expenseDates.length),
      categoryTotals: {
        for (final category in ExpenseCategory.values)
          category: ReconciliationService.money(categoryTotals[category] ?? 0),
      },
      monthlyTotals: orderedMonthlyTotals,
      monthlyCategoryTotals: orderedMonthlyCategories,
    );
  }

  static Future<DateRangeAnalytics> dateRange({
    required String siteId,
    required DateTime startDate,
    required DateTime endDate,
    Set<ExpenseCategory> categories = const {},
    String search = '',
  }) async {
    final expenses = await DatabaseHelper.instance.getExpensesForSiteInRange(
      siteId,
      startDate: startDate,
      endDate: endDate,
      categories: categories,
      search: search,
    );
    final totals = <ExpenseCategory, double>{};
    for (final expense in expenses) {
      totals.update(
        expense.category,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    return DateRangeAnalytics(
      startDate: startDate,
      endDate: endDate,
      expenses: expenses,
      categoryTotals: totals,
    );
  }

  static Future<MonthlyExpenseMatrix> monthlyMatrix(String siteId) async {
    final source = await DatabaseHelper.instance.getMonthlyCategoryMatrix(
      siteId,
    );
    final months = source.keys.toList()..sort();
    final rows = <ExpenseCategory, Map<String, double>>{};
    for (final category in ExpenseCategory.values) {
      rows[category] = {
        for (final month in months)
          month: ReconciliationService.money(source[month]?[category] ?? 0),
      };
    }
    return MonthlyExpenseMatrix(months: months, categoryRows: rows);
  }
}
