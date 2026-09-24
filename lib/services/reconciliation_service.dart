import '../models/cash_float.dart';

/// Pure, deterministic business rules for expense and cash reconciliation.
///
/// All monetary results are rounded to two decimal places before comparison so
/// floating-point noise can never turn a matched cash count into a mismatch.
class ReconciliationService {
  const ReconciliationService._();

  static double money(double value) => (value * 100).roundToDouble() / 100;

  static double lineTotal({
    required double quantity,
    required double unitPrice,
  }) {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be greater than 0');
    }
    if (unitPrice < 0) {
      throw ArgumentError.value(unitPrice, 'unitPrice', 'Cannot be negative');
    }
    return money(quantity * unitPrice);
  }

  static ReconciliationResult reconcile({
    required double openingBalance,
    required double floatReceived,
    required Iterable<double> lineItemTotals,
    required double reportedClosingBalance,
  }) {
    final totalExpenses = money(
      lineItemTotals.fold<double>(0, (sum, value) => sum + value),
    );
    final expected = money(openingBalance + floatReceived - totalExpenses);
    final variance = money(reportedClosingBalance - expected);
    return ReconciliationResult(
      totalExpenses: totalExpenses,
      expectedClosingBalance: expected,
      variance: variance,
      status: variance == 0 ? CashFloatStatus.ok : CashFloatStatus.check,
      isOutOfPocketDeficit: expected < 0,
    );
  }
}

class ReconciliationResult {
  final double totalExpenses;
  final double expectedClosingBalance;
  final double variance;
  final CashFloatStatus status;
  final bool isOutOfPocketDeficit;

  const ReconciliationResult({
    required this.totalExpenses,
    required this.expectedClosingBalance,
    required this.variance,
    required this.status,
    required this.isOutOfPocketDeficit,
  });

  String get statusLabel => status.label;

  String? get deficitLabel => isOutOfPocketDeficit
      ? 'Site Supervisor Deficit / Out-of-pocket Advance'
      : null;
}
