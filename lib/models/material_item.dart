enum MaterialCategory { material, equipment, delivery, other }

extension MaterialCategoryX on MaterialCategory {
  String get label {
    switch (this) {
      case MaterialCategory.material:
        return 'Material';
      case MaterialCategory.equipment:
        return 'Equipment';
      case MaterialCategory.delivery:
        return 'Delivery';
      case MaterialCategory.other:
        return 'Other';
    }
  }
}

class MaterialItem {
  final String id;
  final String logId;
  final String itemName;
  final double quantity;
  final String? unit;
  final MaterialCategory category;

  MaterialItem({
    required this.id,
    required this.logId,
    required this.itemName,
    required this.quantity,
    this.unit,
    this.category = MaterialCategory.material,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'log_id': logId,
    'item_name': itemName,
    'quantity': quantity,
    'unit': unit,
    'category': category.name,
  };

  factory MaterialItem.fromMap(Map<String, dynamic> map) => MaterialItem(
    id: map['id'],
    logId: map['log_id'],
    itemName: map['item_name'],
    quantity: (map['quantity'] as num).toDouble(),
    unit: map['unit'],
    category: MaterialCategory.values.firstWhere(
      (c) => c.name == map['category'],
      orElse: () => MaterialCategory.material,
    ),
  );
}
