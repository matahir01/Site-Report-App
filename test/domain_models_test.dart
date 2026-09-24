import 'package:flutter_test/flutter_test.dart';
import 'package:site_daily_log/models/daily_site_report_meta.dart';
import 'package:site_daily_log/models/expense.dart';

void main() {
  test('expense map always persists quantity multiplied by unit price', () {
    final expense = Expense(
      id: 'expense-1',
      siteId: 'site-1',
      date: DateTime(2026, 9, 24),
      category: ExpenseCategory.toolsAndEquipment,
      amount: 0,
      quantity: 2.5,
      unitPrice: 1250.555,
      description: 'Cutting discs',
      unit: 'pack',
    );

    expect(expense.calculatedTotal, 3126.39);
    expect(expense.toMap()['amount'], 3126.39);
    expect(expense.toMap()['total_amount'], 3126.39);
    expect(expense.toMap()['category_id'], 6);
  });

  test('all real-signature paths survive report metadata round trip', () {
    const meta = DailySiteReportMeta(
      dailyLogId: 'log-1',
      preparedSignaturePath: '/private/signatures/prepared.png',
      reviewedSignaturePath: '/private/signatures/reviewed.jpg',
      approvedSignaturePath: '/private/signatures/approved.png',
    );

    final restored = DailySiteReportMeta.fromMap(meta.toMap());

    expect(restored.preparedSignaturePath, meta.preparedSignaturePath);
    expect(restored.reviewedSignaturePath, meta.reviewedSignaturePath);
    expect(restored.approvedSignaturePath, meta.approvedSignaturePath);
  });

  test('expense unit defaults to the flat-cost value 1', () {
    final expense = Expense(
      id: 'expense-1',
      siteId: 'site-1',
      date: DateTime(2026, 9, 24),
      category: ExpenseCategory.other,
      amount: 500,
    );

    expect(expense.unit, '1');
    expect(expense.toMap()['unit'], '1');
  });
}
