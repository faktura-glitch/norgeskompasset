import 'meal.dart';
import 'profile.dart';

class MenuMeal {
  final MealType type;
  final String name;
  final double weightGrams;
  final double calories;
  const MenuMeal(this.type, this.name, this.weightGrams, this.calories);
}

class FoodMenu {
  final String id;
  final String name;
  final List<String> tags;
  final List<MenuMeal> meals;
  final Set<String> allergens;
  final bool needsCooling;
  final String? note;

  const FoodMenu({
    required this.id,
    required this.name,
    required this.tags,
    required this.meals,
    this.allergens = const {},
    this.needsCooling = false,
    this.note,
  });

  double get totalWeightGrams =>
      meals.fold(0.0, (sum, m) => sum + m.weightGrams);
  double get totalCalories => meals.fold(0.0, (sum, m) => sum + m.calories);

  List<String> conflictsWith(
    UserProfile profile,
    Iterable<String> preferences,
  ) {
    final diet = [...profile.dietTags, ...preferences].join(' ').toLowerCase();
    return [
      if (diet.contains('vegansk') && !tags.contains('Vegansk'))
        'Ikke et vegansk forslag',
      if (!diet.contains('vegansk') &&
          diet.contains('vegetar') &&
          !tags.contains('Vegetar') &&
          !tags.contains('Vegansk'))
        'Ikke et vegetarisk forslag',
      if (diet.contains('gluten') && !tags.contains('Glutenfritt forslag'))
        'Ikke merket som glutenfritt forslag',
      if (diet.contains('laktose') &&
          !tags.contains('Laktosefritt forslag') &&
          !tags.contains('Vegansk'))
        'Ikke merket som laktosefritt forslag',
      if ((profile.nutAllergy ||
              diet.contains('nøtteallerg') ||
              diet.contains('nøttefri')) &&
          (allergens.contains('Nøtter') || allergens.contains('Peanøtter')))
        'Oppførte nøtter eller peanøtter',
    ];
  }

  List<PlannedMeal> createMeals(int day, String Function() nextId) => [
    for (final meal in meals)
      PlannedMeal(
        id: nextId(),
        day: day,
        type: meal.type,
        name: meal.name,
        gramsPerPerson: meal.weightGrams,
        kcalPer100g: meal.weightGrams > 0
            ? meal.calories * 100 / meal.weightGrams
            : 0,
        userEdited: true,
        sourceMenuId: id,
        notes:
            'Utgangspunkt: $name. Mengde og energi er estimater. '
            'Kontroller ingredienser, allergener og oppbevaring.',
      ),
  ];
}
