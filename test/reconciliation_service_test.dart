import 'package:flutter_test/flutter_test.dart';
import 'package:site_daily_log/models/cash_float.dart';
import 'package:site_daily_log/services/reconciliation_service.dart';

void main() {
  group('ReconciliationService', () {
    test('calculates a strict line item total', () {
      expect(
        ReconciliationService.lineTotal(quantity: 2.5, unitPrice: 1200),
        3000,
      );
    });

    test('matches when reported and expected balances agree', () {
      final result = ReconciliationService.reconcile(
        openingBalance: 0,
        floatReceived: 100000,
        lineItemTotals: const [2000, 3300],
        reportedClosingBalance: 94700,
      );

      expect(result.totalExpenses, 5300);
      expect(result.expectedClosingBalance, 94700);
      expect(result.variance, 0);
      expect(result.status, CashFloatStatus.ok);
      expect(result.isOutOfPocketDeficit, isFalse);
    });

    test('flags mismatch and out-of-pocket deficit independently', () {
      final result = ReconciliationService.reconcile(
        openingBalance: 1000,
        floatReceived: 0,
        lineItemTotals: const [1500],
        reportedClosingBalance: -450,
      );

      expect(result.expectedClosingBalance, -500);
      expect(result.variance, 50);
      expect(result.status, CashFloatStatus.check);
      expect(result.isOutOfPocketDeficit, isTrue);
      expect(
        result.deficitLabel,
        'Site Supervisor Deficit / Out-of-pocket Advance',
      );
    });

    test('rounds currency before comparing variance', () {
      final result = ReconciliationService.reconcile(
        openingBalance: 0.1,
        floatReceived: 0.2,
        lineItemTotals: const [0.1],
        reportedClosingBalance: 0.2,
      );

      expect(result.variance, 0);
      expect(result.status, CashFloatStatus.ok);
    });

    test('rejects invalid quantities and prices', () {
      expect(
        () => ReconciliationService.lineTotal(quantity: 0, unitPrice: 10),
        throwsArgumentError,
      );
      expect(
        () => ReconciliationService.lineTotal(quantity: 1, unitPrice: -1),
        throwsArgumentError,
      );
    });
  });
}
