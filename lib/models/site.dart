class Site {
  final String id;
  final String projectId;
  final String name;
  final String? address;
  final DateTime createdAt;

  Site({
    required this.id,
    required this.projectId,
    required this.name,
    this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'address': address,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Site.fromMap(Map<String, dynamic> map) => Site(
    id: map['id'],
    projectId: map['projectId'],
    name: map['name'],
    address: map['address'],
    createdAt: DateTime.parse(map['createdAt']),
  );
}
