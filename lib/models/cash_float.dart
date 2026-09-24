enum CashFloatStatus { ok, check }

extension CashFloatStatusX on CashFloatStatus {
  String get dbValue => this == CashFloatStatus.ok ? 'OK' : 'CHECK / MISMATCH';

  String get label => dbValue;

  static CashFloatStatus fromDb(String value) =>
      value == 'OK' ? CashFloatStatus.ok : CashFloatStatus.check;
}

/// A daily cash-float reconciliation for a site.
class CashFloat {
  final String id;
  final String siteId;
  final DateTime date;
  final double openingBalance;
  final double floatReceived;
  final double totalExpenses;
  final double reportedClosingBalance;
  final String? notes;

  CashFloat({
    required this.id,
    required this.siteId,
    required this.date,
    this.openingBalance = 0.0,
    this.floatReceived = 0.0,
    this.totalExpenses = 0.0,
    this.reportedClosingBalance = 0.0,
    this.notes,
  });

  double get expectedClosingBalance =>
      _roundCurrency(openingBalance + floatReceived - totalExpenses);

  double get variance =>
      _roundCurrency(reportedClosingBalance - expectedClosingBalance);

  CashFloatStatus get status =>
      variance == 0 ? CashFloatStatus.ok : CashFloatStatus.check;

  bool get isOutOfPocketDeficit => expectedClosingBalance < 0;

  String? get deficitLabel => isOutOfPocketDeficit
      ? 'Site Supervisor Deficit / Out-of-pocket Advance'
      : null;

  static double _roundCurrency(double value) =>
      (value * 100).roundToDouble() / 100;

  Map<String, dynamic> toMap() => {
    'id': id,
    'site_id': siteId,
    'date': date.toIso8601String(),
    'entry_date': date.toIso8601String().split('T').first,
    'opening_balance': openingBalance,
    'float_received': floatReceived,
    'total_expenses': totalExpenses,
    'expected_closing_balance': expectedClosingBalance,
    'reported_closing_balance': reportedClosingBalance,
    'variance': variance,
    'status': status.dbValue,
    'notes': notes,
  };

  factory CashFloat.fromMap(Map<String, dynamic> map) => CashFloat(
    id: map['id'],
    siteId: map['site_id'],
    date: DateTime.parse(map['date']),
    openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
    floatReceived: (map['float_received'] as num?)?.toDouble() ?? 0.0,
    totalExpenses: (map['total_expenses'] as num?)?.toDouble() ?? 0.0,
    reportedClosingBalance:
        (map['reported_closing_balance'] as num?)?.toDouble() ?? 0.0,
    notes: map['notes'],
  );
}
