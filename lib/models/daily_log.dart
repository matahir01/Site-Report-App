class DailyLog {
  final String id;
  final String siteId;
  final DateTime date;
  final String? weather;
  final int? crewCount;
  final String? workCompleted;
  final String? issues;
  final List<String> photoPaths;
  final double? lat;
  final double? lng;
  final bool isSynced;

  DailyLog({
    required this.id,
    required this.siteId,
    required this.date,
    this.weather,
    this.crewCount,
    this.workCompleted,
    this.issues,
    this.photoPaths = const [],
    this.lat,
    this.lng,
    this.isSynced = false,
  });

  double? get latitude => lat;
  double? get longitude => lng;

  DailyLog copyWith({
    String? weather,
    int? crewCount,
    String? workCompleted,
    String? issues,
    List<String>? photoPaths,
    double? lat,
    double? lng,
    bool? isSynced,
  }) {
    return DailyLog(
      id: id,
      siteId: siteId,
      date: date,
      weather: weather ?? this.weather,
      crewCount: crewCount ?? this.crewCount,
      workCompleted: workCompleted ?? this.workCompleted,
      issues: issues ?? this.issues,
      photoPaths: photoPaths ?? this.photoPaths,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'siteId': siteId,
    'date': date.toIso8601String(),
    'weather': weather,
    'crewCount': crewCount,
    'workCompleted': workCompleted,
    'issues': issues,
    'photoPaths': photoPaths.join('|'),
    'lat': lat,
    'lng': lng,
    'is_synced': isSynced ? 1 : 0,
  };

  factory DailyLog.fromMap(Map<String, dynamic> map) => DailyLog(
    id: map['id'],
    siteId: map['siteId'],
    date: DateTime.parse(map['date']),
    weather: map['weather'],
    crewCount: map['crewCount'],
    workCompleted: map['workCompleted'],
    issues: map['issues'],
    photoPaths:
        (map['photoPaths'] as String?)
            ?.split('|')
            .where((e) => e.isNotEmpty)
            .toList() ??
        [],
    lat: map['lat'] == null ? null : (map['lat'] as num).toDouble(),
    lng: map['lng'] == null ? null : (map['lng'] as num).toDouble(),
    isSynced: (map['is_synced'] as int?) == 1,
  );
}
