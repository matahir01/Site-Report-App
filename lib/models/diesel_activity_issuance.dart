/// A single line of diesel issued to a non-dipped activity (generator,
/// mixer, welding set, etc.) on a given daily log — kept separate from
/// [EquipmentDippingLog] so the sitewide diesel balance can account for
/// fuel that never passed through a dipped machine.
class DieselActivityIssuance {
  final String id;
  final String dailyLogId;
  final String activityName;
  final double litresIssued;

  DieselActivityIssuance({
    required this.id,
    required this.dailyLogId,
    required this.activityName,
    this.litresIssued = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'daily_log_id': dailyLogId,
    'activity_name': activityName,
    'litres_issued': litresIssued,
  };

  factory DieselActivityIssuance.fromMap(Map<String, dynamic> map) =>
      DieselActivityIssuance(
        id: map['id'],
        dailyLogId: map['daily_log_id'],
        activityName: map['activity_name'],
        litresIssued: (map['litres_issued'] as num?)?.toDouble() ?? 0.0,
      );
}
