enum PackingCategory {
  clothing,
  shelterSleeping,
  foodKitchen,
  navigation,
  safetyFirstAid,
  personal,
  additional,
  food,
  water,
}

extension PackingCategoryX on PackingCategory {
  String get label => switch (this) {
    PackingCategory.clothing => 'Klær',
    PackingCategory.shelterSleeping => 'Telt og soving',
    PackingCategory.foodKitchen => 'Mat og kjøkken',
    PackingCategory.navigation => 'Navigasjon og kommunikasjon',
    PackingCategory.safetyFirstAid => 'Sikkerhet og førstehjelp',
    PackingCategory.personal => 'Personlige artikler',
    PackingCategory.additional => 'Ekstra utstyr',
    PackingCategory.food => 'Mat (forbruksvare)',
    PackingCategory.water => 'Vann',
  };
}

enum PackingPriority { required, recommended, optional }

extension PackingPriorityX on PackingPriority {
  String get label => switch (this) {
    PackingPriority.required => 'Nødvendig',
    PackingPriority.recommended => 'Anbefalt',
    PackingPriority.optional => 'Valgfri',
  };
}

class PackingItem {
  final String id;
  String name;
  PackingCategory category;
  double quantity;
  double unitWeightGrams;
  bool packed;
  PackingPriority priority;

  /// Worn on the body (boots, hiking clothes) rather than carried
  /// in the pack — excluded from pack weight but still carried mass.
  bool worn;

  /// Why the item was recommended (trip-condition link), shown to the user.
  String? reason;
  bool userAdded;
  bool needsAcquisition;
  bool nameEdited;
  bool quantityEdited;
  bool priorityEdited;
  bool weightEdited;

  /// Consumables (food, water, fuel, toilet paper) shrink during the
  /// trip and are reported separately from base weight.
  bool consumable;

  /// Consumables (food/water or explicitly flagged) are reported
  /// separately from carried equipment.
  bool get isConsumable =>
      consumable ||
      category == PackingCategory.food ||
      category == PackingCategory.water;

  double get totalWeightGrams => quantity * unitWeightGrams;

  PackingItem({
    required this.id,
    required this.name,
    required this.category,
    this.quantity = 1,
    this.unitWeightGrams = 0,
    this.packed = false,
    this.priority = PackingPriority.recommended,
    this.worn = false,
    this.reason,
    this.userAdded = false,
    this.needsAcquisition = false,
    this.nameEdited = false,
    this.quantityEdited = false,
    this.priorityEdited = false,
    this.weightEdited = false,
    this.consumable = false,
  });

  PackingItem copy() => PackingItem(
    id: id,
    name: name,
    category: category,
    quantity: quantity,
    unitWeightGrams: unitWeightGrams,
    packed: packed,
    priority: priority,
    worn: worn,
    reason: reason,
    userAdded: userAdded,
    needsAcquisition: needsAcquisition,
    nameEdited: nameEdited,
    quantityEdited: quantityEdited,
    priorityEdited: priorityEdited,
    weightEdited: weightEdited,
    consumable: consumable,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'quantity': quantity,
    'weight': unitWeightGrams,
    'packed': packed,
    'priority': priority.name,
    'worn': worn,
    'reason': reason,
    'userAdded': userAdded,
    'needsAcquisition': needsAcquisition,
    if (nameEdited) 'nameEdited': true,
    if (quantityEdited) 'quantityEdited': true,
    if (priorityEdited) 'priorityEdited': true,
    if (weightEdited) 'weightEdited': true,
    'consumable': consumable,
  };

  factory PackingItem.fromJson(Map<String, dynamic> j) => PackingItem(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    category:
        PackingCategory.values.asNameMap()[j['category']] ??
        PackingCategory.additional,
    quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
    unitWeightGrams: (j['weight'] as num?)?.toDouble() ?? 0,
    packed: j['packed'] as bool? ?? false,
    priority:
        PackingPriority.values.asNameMap()[j['priority']] ??
        PackingPriority.recommended,
    worn: j['worn'] as bool? ?? false,
    reason: j['reason'] as String?,
    userAdded: j['userAdded'] as bool? ?? false,
    needsAcquisition: j['needsAcquisition'] as bool? ?? false,
    nameEdited: j['nameEdited'] as bool? ?? false,
    quantityEdited: j['quantityEdited'] as bool? ?? false,
    priorityEdited: j['priorityEdited'] as bool? ?? false,
    weightEdited: j['weightEdited'] as bool? ?? false,
    consumable: j['consumable'] as bool? ?? false,
  );
}

/// How ready the pack is. Missing safety or navigation gear blocks
/// "ready" harder than other required items.
enum PackReadiness { ready, almost, notReady }

/// Categories where a missing required item makes the trip unsafe,
/// not just less comfortable.
const safetyCriticalCategories = {
  PackingCategory.safetyFirstAid,
  PackingCategory.navigation,
};

extension PackingListX on Iterable<PackingItem> {
  /// Required items still to go in the pack (worn items never do).
  Iterable<PackingItem> get missingRequired => where(
    (i) => !i.packed && !i.worn && i.priority == PackingPriority.required,
  );

  int get missingSafetyCount => missingRequired
      .where((i) => safetyCriticalCategories.contains(i.category))
      .length;

  PackReadiness get readiness {
    if (missingSafetyCount > 0) return PackReadiness.notReady;
    if (missingRequired.isNotEmpty) return PackReadiness.almost;
    return PackReadiness.ready;
  }

  /// Pack weight per category, heaviest first. Worn items are left
  /// out — they are carried on the body, not in the pack.
  List<(PackingCategory, double)> get packWeightByCategory {
    final sums = <PackingCategory, double>{};
    for (final i in where((i) => !i.worn)) {
      sums[i.category] = (sums[i.category] ?? 0) + i.totalWeightGrams;
    }
    return [
      for (final e in sums.entries)
        if (e.value > 0) (e.key, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }
}
