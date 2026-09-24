enum AttendanceStatus { present, absent, halfDay }

extension AttendanceStatusX on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.halfDay:
        return 'Half-Day';
    }
  }

  String get dbValue => label;

  static AttendanceStatus fromDb(String value) {
    switch (value) {
      case 'Present':
        return AttendanceStatus.present;
      case 'Half-Day':
        return AttendanceStatus.halfDay;
      case 'Absent':
      default:
        return AttendanceStatus.absent;
    }
  }
}

/// A single worker's check-in status for a single daily log entry.
class Attendance {
  final String id;
  final String dailyLogId;
  final String workerId;
  final AttendanceStatus status;
  final String? notes;

  Attendance({
    required this.id,
    required this.dailyLogId,
    required this.workerId,
    required this.status,
    this.notes,
  });

  Attendance copyWith({AttendanceStatus? status, String? notes}) => Attendance(
    id: id,
    dailyLogId: dailyLogId,
    workerId: workerId,
    status: status ?? this.status,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'daily_log_id': dailyLogId,
    'worker_id': workerId,
    'status': status.dbValue,
    'notes': notes,
  };

  factory Attendance.fromMap(Map<String, dynamic> map) => Attendance(
    id: map['id'],
    dailyLogId: map['daily_log_id'],
    workerId: map['worker_id'],
    status: AttendanceStatusX.fromDb(map['status']),
    notes: map['notes'],
  );
}
