import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/meal.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/meal_planner.dart';
import 'package:norgeskompasset/services/packing_engine.dart';

Trip _hutToHut(
  List<CabinType> nights, {
  CabinType base = CabinType.selfService,
}) {
  final start = DateTime(2027, 7, 10);
  return Trip(id: 'h', accommodation: AccommodationType.cabin)
    ..cabinType = base
    ..nightCabins = nights
    ..startDate = start
    ..endDate = start.add(const Duration(days: 3));
}

Set<String> _ids(Trip t) => {for (final i in PackingEngine().generate(t)) i.id};

void main() {
  const mixed = [
    CabinType.selfService,
    CabinType.selfService,
    CabinType.staffed,
  ];

  test('hyttetype per natt styrer pakkelisten', () {
    final trip = _hutToHut(mixed);
    expect(trip.cabinNights, mixed);
    expect(trip.accommodationLabel, 'Hytte: 2 selvbetjent, 1 betjent');
    final items = {for (final i in PackingEngine().generate(trip)) i.id: i};
    expect(items.containsKey('hutsnacks'), isFalse);
    expect(items['hutkitchen']?.reason, contains('natt 1 og 2'));
    expect(items['hutpayment']?.reason, contains('natt 1 og 2'));
    expect(items['hutkey']?.reason, contains('natt 3 betjent'));
  });

  test('like netter gir samme liste som én hyttetype for hele turen', () {
    final perNight = _hutToHut(const [
      CabinType.staffed,
      CabinType.staffed,
      CabinType.staffed,
    ]);
    final single = _hutToHut(const [], base: CabinType.staffed);
    expect(_ids(perNight), _ids(single));
    expect(perNight.accommodationLabel, 'Hytte');
  });

  test('betjent hytte serverer middag og neste frokost', () {
    final plan = MealPlanner.generate(_hutToHut(mixed));
    PlannedMeal meal(int day, MealType type) =>
        plan.meals.firstWhere((m) => m.day == day && m.type == type);
    expect(meal(3, MealType.dinner).served, isTrue);
    expect(meal(4, MealType.breakfast).served, isTrue);
    expect(meal(2, MealType.dinner).served, isFalse);
    expect(meal(3, MealType.breakfast).served, isFalse);
    expect(plan.shoppingList.any((s) => s.contains('Servert')), isFalse);
  });

  test('hyttetype per natt overlever lagring og synk', () {
    final trip = _hutToHut(mixed);
    expect(Trip.decode(trip.encode()).nightCabins, mixed);
    expect(Trip.fromSyncJson(trip.toSyncJson()).nightCabins, mixed);
  });
}
