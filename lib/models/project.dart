class Project {
  final String id;
  final String name;
  final String? client;
  final String? siteLocation;
  final String? gpsCoordinates;
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    this.client,
    this.siteLocation,
    this.gpsCoordinates,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'client': client,
    'project_name': name,
    'client_name': client,
    'site_location': siteLocation,
    'gps_coordinates': gpsCoordinates,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Project.fromMap(Map<String, dynamic> map) => Project(
    id: map['id'],
    name: (map['project_name'] ?? map['name']) as String,
    client: (map['client_name'] ?? map['client']) as String?,
    siteLocation: map['site_location'] as String?,
    gpsCoordinates: map['gps_coordinates'] as String?,
    createdAt: DateTime.parse(map['createdAt']),
  );
}
