import 'expense.dart';

class DashboardSnapshot {
  final double totalSpend;
  final double totalFloatReceived;
  final double currentCashBalance;
  final ExpenseCategory? highestCostCategory;
  final double highestCostCategoryPercentage;
  final double averageDailySpend;
  final Map<ExpenseCategory, double> categoryTotals;
  final Map<String, double> monthlyTotals;
  final Map<String, Map<ExpenseCategory, double>> monthlyCategoryTotals;

  const DashboardSnapshot({
    required this.totalSpend,
    required this.totalFloatReceived,
    required this.currentCashBalance,
    required this.highestCostCategory,
    required this.highestCostCategoryPercentage,
    required this.averageDailySpend,
    required this.categoryTotals,
    required this.monthlyTotals,
    required this.monthlyCategoryTotals,
  });
}

class DateRangeAnalytics {
  final DateTime startDate;
  final DateTime endDate;
  final List<Expense> expenses;
  final Map<ExpenseCategory, double> categoryTotals;

  const DateRangeAnalytics({
    required this.startDate,
    required this.endDate,
    required this.expenses,
    required this.categoryTotals,
  });

  int get itemCount => expenses.length;
  double get total =>
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount);

  double percentageFor(ExpenseCategory category) {
    if (total == 0) return 0;
    return (categoryTotals[category] ?? 0) / total * 100;
  }
}

class MonthlyExpenseMatrix {
  final List<String> months;
  final Map<ExpenseCategory, Map<String, double>> categoryRows;

  const MonthlyExpenseMatrix({
    required this.months,
    required this.categoryRows,
  });

  double categoryTotal(ExpenseCategory category) =>
      categoryRows[category]?.values.fold<double>(
        0,
        (sum, value) => sum + value,
      ) ??
      0;

  double monthTotal(String month) => categoryRows.values.fold<double>(
    0,
    (sum, row) => sum + (row[month] ?? 0),
  );

  double get grandTotal =>
      months.fold<double>(0, (sum, month) => sum + monthTotal(month));
}
