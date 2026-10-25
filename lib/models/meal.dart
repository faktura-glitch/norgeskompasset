enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeX on MealType {
  String get label => switch (this) {
    MealType.breakfast => 'Frokost',
    MealType.lunch => 'Lunsj',
    MealType.dinner => 'Middag',
    MealType.snack => 'Snacks og energi',
  };
}

/// One planned meal slot. [gramsPerPerson] is total dry/packed weight,
/// [kcalPer100g] the estimated energy density (0 = unknown).
class PlannedMeal {
  final String id;
  int day; // 1-based hiking day
  MealType type;
  String name;
  double gramsPerPerson;
  double kcalPer100g;
  String? notes;
  bool userEdited;
  String? sourceMenuId;

  PlannedMeal({
    required this.id,
    required this.day,
    required this.type,
    required this.name,
    this.gramsPerPerson = 0,
    this.kcalPer100g = 0,
    this.notes,
    this.userEdited = false,
    this.sourceMenuId,
  });

  /// Estimated calories per person for this meal (0 when unknown).
  double get kcalPerPerson => gramsPerPerson * kcalPer100g / 100;

  Map<String, dynamic> toJson() => {
    'id': id,
    'day': day,
    'type': type.name,
    'name': name,
    'grams': gramsPerPerson,
    'kcal': kcalPer100g,
    'notes': notes,
    'userEdited': userEdited,
    'sourceMenuId': sourceMenuId,
  };

  factory PlannedMeal.fromJson(Map<String, dynamic> j) => PlannedMeal(
    id: j['id'] as String,
    day: j['day'] as int? ?? 1,
    type: MealType.values.asNameMap()[j['type']] ?? MealType.snack,
    name: j['name'] as String? ?? '',
    gramsPerPerson: (j['grams'] as num?)?.toDouble() ?? 0,
    kcalPer100g: (j['kcal'] as num?)?.toDouble() ?? 0,
    notes: j['notes'] as String?,
    userEdited: j['userEdited'] as bool? ?? false,
    sourceMenuId: j['sourceMenuId'] as String?,
  );
}

class MealPlan {
  int days;
  int people;
  List<PlannedMeal> meals;
  Set<String> checkedShoppingItems;

  /// Free-form dietary preferences/restrictions, e.g. 'vegetar', 'glutenfri'.
  List<String> dietaryPreferences;

  /// Liters of water carried per person per day (user-adjustable estimate).
  double waterLitersPerPersonDay;

  MealPlan({
    this.days = 1,
    this.people = 1,
    this.meals = const [],
    this.dietaryPreferences = const [],
    this.waterLitersPerPersonDay = 1.5,
    Set<String>? checkedShoppingItems,
  }) : checkedShoppingItems = checkedShoppingItems ?? {};

  double get totalFoodWeightGrams =>
      meals.fold(0.0, (s, m) => s + m.gramsPerPerson * people);

  double get totalWaterWeightGrams =>
      waterLitersPerPersonDay * days * people * 1000;

  /// Estimated calories per person for a given day (sums only meals
  /// with known energy density).
  double kcalPerPersonDay(int day) =>
      meals.where((m) => m.day == day).fold(0.0, (s, m) => s + m.kcalPerPerson);

  /// Estimated calories per person across the whole trip.
  double get totalKcalPerPerson =>
      meals.fold(0.0, (s, m) => s + m.kcalPerPerson);

  List<String> get shoppingList {
    final list = meals
        .where((m) => m.name.trim().isNotEmpty)
        .map(
          (m) =>
              '${m.name} — dag ${m.day} (${m.type.label.toLowerCase()}, ${(m.gramsPerPerson * people).round()} g'
              '${m.kcalPer100g > 0 ? ', ${(m.kcalPerPerson * people).round()} kcal' : ''})',
        )
        .toList();
    list.sort();
    return list;
  }

  Map<String, dynamic> toJson() => {
    'days': days,
    'people': people,
    'water': waterLitersPerPersonDay,
    'diet': dietaryPreferences,
    'checkedShoppingItems': checkedShoppingItems.toList(),
    'meals': meals.map((m) => m.toJson()).toList(),
  };

  factory MealPlan.fromJson(Map<String, dynamic> j) => MealPlan(
    checkedShoppingItems: (j['checkedShoppingItems'] as List? ?? [])
        .map((e) => e.toString())
        .toSet(),
    days: j['days'] as int? ?? 1,
    people: j['people'] as int? ?? 1,
    waterLitersPerPersonDay: (j['water'] as num?)?.toDouble() ?? 1.5,
    dietaryPreferences: (j['diet'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    meals: (j['meals'] as List? ?? [])
        .map((m) => PlannedMeal.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
  );
}
