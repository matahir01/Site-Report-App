/// A daily dip-stick fuel/oil reading for one piece of machinery, plus
/// engine-hour meter readings used to derive operating hours and specific
/// fuel consumption (burn rate).
class EquipmentDippingLog {
  final String id;
  final String dailyLogId;
  final String equipmentName;
  final double? openingDipCm;
  final double? closingDipCm;
  final double dieselIssuedLitres;
  final double engineOilIssuedLitres;
  final double? openingEngineHours;
  final double? closingEngineHours;

  EquipmentDippingLog({
    required this.id,
    required this.dailyLogId,
    required this.equipmentName,
    this.openingDipCm,
    this.closingDipCm,
    this.dieselIssuedLitres = 0.0,
    this.engineOilIssuedLitres = 0.0,
    this.openingEngineHours,
    this.closingEngineHours,
  });

  double? get dipConsumedCm {
    if (openingDipCm == null || closingDipCm == null) return null;
    return openingDipCm! - closingDipCm!;
  }

  /// Hours the machine actually ran today (closing - opening meter reading).
  double? get operatingHours {
    if (openingEngineHours == null || closingEngineHours == null) return null;
    final hours = closingEngineHours! - openingEngineHours!;
    return hours < 0 ? null : hours;
  }

  /// Specific fuel consumption: litres burned per operating hour.
  /// Null when engine-hour readings aren't available, or when the machine
  /// logged zero operating hours (avoids a divide-by-zero / infinity).
  double? get fuelBurnRateLitresPerHour {
    final hours = operatingHours;
    if (hours == null || hours == 0) return null;
    return dieselIssuedLitres / hours;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'daily_log_id': dailyLogId,
    'equipment_name': equipmentName,
    'opening_dip_cm': openingDipCm,
    'closing_dip_cm': closingDipCm,
    'diesel_issued_litres': dieselIssuedLitres,
    'engine_oil_issued_litres': engineOilIssuedLitres,
    'opening_engine_hours': openingEngineHours,
    'closing_engine_hours': closingEngineHours,
  };

  factory EquipmentDippingLog.fromMap(Map<String, dynamic> map) =>
      EquipmentDippingLog(
        id: map['id'],
        dailyLogId: map['daily_log_id'],
        equipmentName: map['equipment_name'],
        openingDipCm: map['opening_dip_cm'] == null
            ? null
            : (map['opening_dip_cm'] as num).toDouble(),
        closingDipCm: map['closing_dip_cm'] == null
            ? null
            : (map['closing_dip_cm'] as num).toDouble(),
        dieselIssuedLitres:
            (map['diesel_issued_litres'] as num?)?.toDouble() ?? 0.0,
        engineOilIssuedLitres:
            (map['engine_oil_issued_litres'] as num?)?.toDouble() ?? 0.0,
        openingEngineHours: map['opening_engine_hours'] == null
            ? null
            : (map['opening_engine_hours'] as num).toDouble(),
        closingEngineHours: map['closing_engine_hours'] == null
            ? null
            : (map['closing_engine_hours'] as num).toDouble(),
      );
}
