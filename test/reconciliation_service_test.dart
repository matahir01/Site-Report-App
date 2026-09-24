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

    test('treats a negative position as engineer advance, not negative cash', () {
      final result = ReconciliationService.reconcile(
        openingBalance: 1000,
        floatReceived: 0,
        lineItemTotals: const [1500],
        reportedClosingBalance: 0,
      );

      expect(result.expectedClosingBalance, -500);
      expect(result.expectedCashClosingBalance, 0);
      expect(result.outOfPocketAdvance, 500);
      expect(result.variance, 0);
      expect(result.status, CashFloatStatus.ok);
      expect(result.isOutOfPocketDeficit, isTrue);
      expect(
        result.deficitLabel,
        'Site Supervisor Deficit / Out-of-pocket Advance',
      );
    });

    test('still flags unaccounted cash after a deficit is funded', () {
      final result = ReconciliationService.reconcile(
        openingBalance: -53070,
        floatReceived: 150000,
        lineItemTotals: const [6500],
        reportedClosingBalance: 6500,
      );

      expect(result.expectedClosingBalance, 90430);
      expect(result.expectedCashClosingBalance, 90430);
      expect(result.outOfPocketAdvance, 0);
      expect(result.variance, -83930);
      expect(result.status, CashFloatStatus.check);
      expect(result.isOutOfPocketDeficit, isFalse);
    });

    test('CashFloat preserves signed carry-forward while reconciling cash', () {
      final cashFloat = CashFloat(
        id: 'cash-1',
        siteId: 'site-1',
        date: DateTime(2026, 9, 24),
        openingBalance: 0,
        floatReceived: 0,
        totalExpenses: 53070,
        reportedClosingBalance: 0,
      );

      expect(cashFloat.expectedClosingBalance, -53070);
      expect(cashFloat.expectedCashClosingBalance, 0);
      expect(cashFloat.outOfPocketAdvance, 53070);
      expect(cashFloat.variance, 0);
      expect(cashFloat.status, CashFloatStatus.ok);
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
