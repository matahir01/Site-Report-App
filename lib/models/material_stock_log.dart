/// A single stock-ledger line for one material item on one daily log.
class MaterialStockLog {
  final String id;
  final String dailyLogId;
  final String itemName;
  final String unit;
  final double openingBalance;
  final double received;
  final double issued;
  final double closingBalance;

  MaterialStockLog({
    required this.id,
    required this.dailyLogId,
    required this.itemName,
    required this.unit,
    this.openingBalance = 0.0,
    this.received = 0.0,
    this.issued = 0.0,
    double? closingBalance,
  }) : closingBalance = closingBalance ?? (openingBalance + received - issued);

  double get computedClosingBalance => openingBalance + received - issued;

  bool get hasVariance =>
      (closingBalance - computedClosingBalance).abs() > 0.001;

  Map<String, dynamic> toMap() => {
    'id': id,
    'daily_log_id': dailyLogId,
    'item_name': itemName,
    'unit': unit,
    'opening_balance': openingBalance,
    'received': received,
    'issued': issued,
    'closing_balance': closingBalance,
  };

  factory MaterialStockLog.fromMap(Map<String, dynamic> map) =>
      MaterialStockLog(
        id: map['id'],
        dailyLogId: map['daily_log_id'],
        itemName: map['item_name'],
        unit: map['unit'],
        openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
        received: (map['received'] as num?)?.toDouble() ?? 0.0,
        issued: (map['issued'] as num?)?.toDouble() ?? 0.0,
        closingBalance: (map['closing_balance'] as num?)?.toDouble() ?? 0.0,
      );
}

const List<Map<String, String>> kStandardMaterialItems = [
  {'name': 'Y25mm Rebar', 'unit': 'length'},
  {'name': 'Y20mm Rebar', 'unit': 'length'},
  {'name': 'Y16mm Rebar', 'unit': 'length'},
  {'name': 'Y12mm Rebar', 'unit': 'length'},
  {'name': 'Cement', 'unit': 'Bags'},
  {'name': 'Diesel', 'unit': 'Litres'},
  {'name': 'Engine Oil', 'unit': 'Litres'},
];
