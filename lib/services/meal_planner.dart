import 'package:uuid/uuid.dart';

import '../models/meal.dart';
import '../models/food_menu.dart';
import '../models/profile.dart';
import '../models/trip.dart';

/// Generates a sensible default meal plan sized to the trip.
/// Gram values are typical dry-weight hiking rations — presented as
/// estimates the user should adjust to appetite and activity level.
class MealPlanner {
  static const _uuid = Uuid();
  static String _id() => _uuid.v4().substring(0, 8);

  static MealPlan applyMenu(
    Trip trip,
    FoodMenu menu, {
    int? day,
    UserProfile? profile,
  }) {
    final previous = trip.mealPlan;
    final days = trip.hikingDays;
    if (trip.participants < 1 ||
        days < 1 ||
        (day != null && (day < 1 || day > days))) {
      throw ArgumentError('Ugyldig dag eller antall personer.');
    }
    final diet =
        previous?.dietaryPreferences ?? profile?.dietTags ?? <String>[];
    final conflicts = menu.conflictsWith(profile ?? UserProfile(), diet);
    if (conflicts.isNotEmpty) throw ArgumentError(conflicts.join('. '));
    final targetDays = day == null ? List.generate(days, (i) => i + 1) : [day];
    final meals = [
      for (final meal in previous?.meals ?? <PlannedMeal>[])
        if (meal.day >= 1 && meal.day <= days && !targetDays.contains(meal.day))
          meal,
      for (final target in targetDays) ...menu.createMeals(target, _id),
    ];
    final result = MealPlan(
      days: days,
      people: trip.participants,
      meals: meals,
      dietaryPreferences: List.of(diet),
      waterLitersPerPersonDay: previous?.waterLitersPerPersonDay ?? 1.5,
    );
    result.checkedShoppingItems.addAll(
      (previous?.checkedShoppingItems ?? <String>{}).intersection(
        result.shoppingList.toSet(),
      ),
    );
    return result;
  }

  /// Default meals per day. Multi-day trips get dinners; day trips get
  /// lunch + snacks only.
  ///
  /// [targetKcalPerDay] is the route-aware energy estimate (distance,
  /// ascent, pack weight, cold). When the default portions land far
  /// below it, generated meal sizes are scaled up — capped at ×1.6 and
  /// rounded to 10 g — so a long, heavy day doesn't silently produce
  /// a day-hike ration. Only freshly generated meals are scaled;
  /// menu-applied or user-edited meals are never rebuilt here.
  static MealPlan generate(
    Trip trip, {
    UserProfile? profile,
    double? targetKcalPerDay,
  }) {
    final days = trip.hikingDays;
    final people = trip.participants;
    final meals = <PlannedMeal>[];
    // Existing plan prefs win; a fresh plan inherits the profile's
    // diet tags so restrictions aren't re-entered for every trip.
    final existing = trip.mealPlan?.dietaryPreferences ?? const [];
    final diet = existing.isNotEmpty
        ? existing
        : (profile?.dietTags ?? const <String>[]);
    final veg = diet.any(
      (d) =>
          d.toLowerCase().contains('vegetar') ||
          d.toLowerCase().contains('vegansk'),
    );
    final dehydrated = diet.isNotEmpty
        ? diet.any((d) => d.toLowerCase().contains('rehydrert'))
        : (profile?.prefersDehydrated ?? false);

    for (var day = 1; day <= days; day++) {
      if (days > 1) {
        meals.add(
          PlannedMeal(
            id: _id(),
            day: day,
            type: MealType.breakfast,
            name: 'Havregrøt med tørket frukt og nøtter',
            gramsPerPerson: 140,
            kcalPer100g: 380,
          ),
        );
        meals.add(
          PlannedMeal(
            id: _id(),
            day: day,
            type: MealType.lunch,
            name: 'Brød/knekkebrød med pålegg og ost',
            gramsPerPerson: 180,
            kcalPer100g: 300,
          ),
        );
        meals.add(
          PlannedMeal(
            id: _id(),
            day: day,
            type: MealType.dinner,
            name: veg
                ? 'Tørket vegetargryte med couscous'
                : dehydrated
                ? 'Turmat (frysetørket middag)'
                : 'Hjemmelaget gryte – tørket og pakkes porsjonsvis',
            gramsPerPerson: 160,
            kcalPer100g: veg ? 400 : (dehydrated ? 460 : 420),
          ),
        );
      } else {
        meals.add(
          PlannedMeal(
            id: _id(),
            day: day,
            type: MealType.lunch,
            name: 'Niste – brød/knekkebrød med pålegg',
            gramsPerPerson: 180,
            kcalPer100g: 300,
          ),
        );
      }
      meals.add(
        PlannedMeal(
          id: _id(),
          day: day,
          type: MealType.snack,
          name: 'Energiblanding: nøtter, sjokolade, tørket frukt',
          gramsPerPerson: days > 1 ? 200 : 150,
          kcalPer100g: 480,
          notes: 'Nødproviant er regnet inn i pakkelisten',
        ),
      );
    }

    // A staffed cabin serves dinner and the next morning's breakfast.
    final nights = trip.cabinNights;
    bool staffedNight(int n) =>
        n >= 1 && n <= nights.length && nights[n - 1] == CabinType.staffed;
    var servedKcal = 0.0;
    for (final m in meals) {
      final served = switch (m.type) {
        MealType.dinner => staffedNight(m.day),
        MealType.breakfast => staffedNight(m.day - 1),
        _ => false,
      };
      if (!served) continue;
      servedKcal += m.kcalPerPerson;
      m
        ..name = 'Servert på betjent hytte'
        ..gramsPerPerson = 0
        ..kcalPer100g = 0
        ..served = true;
    }

    if (targetKcalPerDay != null && meals.isNotEmpty) {
      final planned =
          (meals.fold(0.0, (s, m) => s + m.kcalPerPerson) + servedKcal) / days;
      if (planned > 0 && planned < targetKcalPerDay * 0.85) {
        final factor = (targetKcalPerDay / planned).clamp(1.0, 1.6);
        for (final m in meals) {
          m.gramsPerPerson = (m.gramsPerPerson * factor / 10).round() * 10;
        }
      }
    }

    return MealPlan(
      days: days,
      people: people,
      meals: meals,
      dietaryPreferences: diet,
      waterLitersPerPersonDay: trip.mealPlan?.waterLitersPerPersonDay ?? 1.5,
    );
  }
}
