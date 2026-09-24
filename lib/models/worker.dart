/// A member of a site's crew roster.
class Worker {
  final String id;
  final String siteId;
  final String name;
  final String role;
  final bool isActive;

  Worker({
    required this.id,
    required this.siteId,
    required this.name,
    required this.role,
    this.isActive = true,
  });

  Worker copyWith({String? name, String? role, bool? isActive}) => Worker(
    id: id,
    siteId: siteId,
    name: name ?? this.name,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'site_id': siteId,
    'name': name,
    'role': role,
    'is_active': isActive ? 1 : 0,
  };

  factory Worker.fromMap(Map<String, dynamic> map) => Worker(
    id: map['id'],
    siteId: map['site_id'],
    name: map['name'],
    role: map['role'],
    isActive: (map['is_active'] as int?) != 0,
  );
}

const List<String> kCommonWorkerRoles = [
  'Mason',
  'Steel Fixer',
  'Carpenter',
  'Laborer',
  'Electrician',
  'Plumber',
  'Welder',
  'Machine Operator',
  'Site Supervisor',
  'Other',
];
