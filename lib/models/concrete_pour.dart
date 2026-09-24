/// A single concrete pour / slump test QC record logged against a daily
/// log entry — e.g. "First Floor Slab, Grade C25, 12.5m³, 75mm slump,
/// 6 cubes cast, Batch Ticket #4471".
class ConcretePour {
  final String id;
  final String dailyLogId;
  final String elementName; // e.g. "First Floor Slab", "Column C4"
  final String concreteGrade; // e.g. "C25", "C30", "C40"
  final double volumeM3;
  final double? slumpMm;
  final int cubesCast;
  final String? batchTicketNo;

  ConcretePour({
    required this.id,
    required this.dailyLogId,
    required this.elementName,
    required this.concreteGrade,
    required this.volumeM3,
    this.slumpMm,
    this.cubesCast = 0,
    this.batchTicketNo,
  });

  ConcretePour copyWith({
    String? elementName,
    String? concreteGrade,
    double? volumeM3,
    double? slumpMm,
    int? cubesCast,
    String? batchTicketNo,
  }) {
    return ConcretePour(
      id: id,
      dailyLogId: dailyLogId,
      elementName: elementName ?? this.elementName,
      concreteGrade: concreteGrade ?? this.concreteGrade,
      volumeM3: volumeM3 ?? this.volumeM3,
      slumpMm: slumpMm ?? this.slumpMm,
      cubesCast: cubesCast ?? this.cubesCast,
      batchTicketNo: batchTicketNo ?? this.batchTicketNo,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'daily_log_id': dailyLogId,
    'element_name': elementName,
    'concrete_grade': concreteGrade,
    'volume_m3': volumeM3,
    'slump_mm': slumpMm,
    'cubes_cast': cubesCast,
    'batch_ticket_no': batchTicketNo,
  };

  factory ConcretePour.fromMap(Map<String, dynamic> map) => ConcretePour(
    id: map['id'],
    dailyLogId: map['daily_log_id'],
    elementName: map['element_name'],
    concreteGrade: map['concrete_grade'],
    volumeM3: (map['volume_m3'] as num).toDouble(),
    slumpMm: map['slump_mm'] == null
        ? null
        : (map['slump_mm'] as num).toDouble(),
    cubesCast: (map['cubes_cast'] as num?)?.toInt() ?? 0,
    batchTicketNo: map['batch_ticket_no'],
  );
}
