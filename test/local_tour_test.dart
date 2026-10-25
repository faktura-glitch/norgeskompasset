import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/models/catalog_trip.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/profile.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:norgeskompasset/screens/find_tours_screen.dart';
import 'package:norgeskompasset/services/meal_planner.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/trip_repository.dart';
import 'package:norgeskompasset/state/app_state.dart';

/// A small two-point route for shared-catalog entries in tests.
HikingRoute _route() => HikingRoute(
  points: [RoutePoint(59.97, 10.73), RoutePoint(60.0, 10.75)],
  source: RouteSource.estimated,
  distanceMeters: 4000,
);

class _MemoryRepository extends TripRepository {
  final saved = <Trip>[];
  bool fail = false;

  @override
  Future<void> saveTrip(Trip trip, {bool syncCloud = true}) async {
    if (fail) throw StateError('Storage unavailable');
    saved.add(Trip.decode(trip.encode()));
  }
}

void main() {
  testWidgets('Find tour opens offline without creating a trip', (
    tester,
  ) async {
    final repo = _MemoryRepository();
    final state = AppState(repo)..localOnly = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: FindToursScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turer delt av brukere'), findsOneWidget);
    // Built-in suggestions are gone — only user-shared tours remain.
    expect(find.text('Sognsvann – Ullevålseter'), findsNothing);
    expect(find.text('Besseggen'), findsNothing);
    expect(find.textContaining('Logg inn fra Mer'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(repo.saved, isEmpty);
    expect(state.trips, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('published import persists before selection and generates provisional packing', () async {
    final repo = _MemoryRepository();
    final state = AppState(repo)
      ..trips = [Trip(id: 'existing')]
      ..currentTripId = 'existing';
    addTearDown(state.dispose);
    final entry = CatalogTrip(
      id: 'shared',
      ownerUid: 'owner',
      name: 'Delt tur',
      route: _route(),
      activity: TripActivity.ski,
      durationDays: 3,
    );
    repo.fail = true;
    await expectLater(
      state.startFromCatalog(entry, startDate: DateTime(2026, 7, 1)),
      throwsStateError,
    );
    expect(state.trips.length, 1);
    expect(state.currentTripId, 'existing');
    repo.fail = false;
    final trip = await state.startFromCatalog(
      entry,
      startDate: DateTime(2026, 7, 1),
    );
    expect(trip.startDate, DateTime.utc(2026, 7, 1));
    // Activity and duration must come from the shared entry so the
    // generated packing/meal plan is built on the right premises.
    expect(trip.activity, TripActivity.ski);
    expect(trip.hikingDays, 3);
    expect(trip.endDate, DateTime.utc(2026, 7, 3));
    expect(trip.packingList, isNotEmpty);
    expect(trip.mealPlan, isNotNull);
    expect(trip.route, isNot(same(entry.route)));
    expect(repo.saved.length, 1);
  });

  test(
    'published import uses confirmed activity, carry and overnight choices',
    () async {
      final state = AppState(_MemoryRepository());
      addTearDown(state.dispose);
      final entry = CatalogTrip(
        id: 'paddle',
        ownerUid: 'owner',
        name: 'Padletur',
        route: _route(),
        activity: TripActivity.foot,
        durationDays: 1,
      );
      final trip = await state.startFromCatalog(
        entry,
        startDate: DateTime(2026, 7, 1),
        activity: TripActivity.paddle,
        carry: CarryMode.canoe,
        accommodation: AccommodationType.tent,
        season: TripSeason.summer,
        participants: 3,
        days: 2,
      );
      expect(trip.participants, 3);
      expect(trip.hikingDays, 2);
      expect(trip.carry, CarryMode.canoe);
      expect(
        trip.packingList.map((i) => i.id),
        containsAll(['pfd', 'drybags']),
      );
      expect(trip.mealPlan!.people, 3);
    },
  );

  test(
    'new route clears outdated conditions and keeps personal plans',
    () async {
      final state = AppState(_MemoryRepository());
      addTearDown(state.dispose);
      final trip = Trip(
        id: 'route',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 2),
      );
      state.trips = [trip];
      state.currentTripId = trip.id;
      trip.packingList = PackingEngine().generate(trip);
      trip.packingList.add(
        PackingItem(
          id: 'mine-sko',
          name: 'Mine sko',
          category: PackingCategory.clothing,
          userAdded: true,
        ),
      );
      trip.mealPlan = MealPlanner.generate(trip);
      trip.mealPlan!.meals.first.userEdited = true;
      final originalMeal = trip.mealPlan!.meals.first;
      trip.avalancheTerrain = false;
      trip.weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: DateTime.now(),
        hours: [],
      );

      await state.importRoute(trip, [
        RoutePoint(60, 8),
        RoutePoint(60.1, 8.1),
      ], []);
      expect(trip.route!.hasRoute, isTrue);
      expect(trip.weather, isEmpty);
      expect(trip.avalancheTerrain, isNull);
      expect(trip.packingList.any((item) => item.id == 'mine-sko'), isTrue);
      expect(trip.mealPlan!.meals.first, same(originalMeal));

      await state.clearRoute(trip);
      expect(trip.route, isNull);
      expect(trip.stages, isEmpty);
      expect(trip.packingList.any((item) => item.id == 'mine-sko'), isTrue);
      expect(trip.mealPlan!.meals.first, same(originalMeal));
    },
  );

  test('first route creates a provisional list and meal plan', () async {
    final repo = _MemoryRepository();
    final state = AppState(repo);
    addTearDown(state.dispose);
    final trip = Trip(id: 'new');
    state.trips = [trip];
    state.currentTripId = trip.id;
    await state.importRoute(trip, [
      RoutePoint(60, 8),
      RoutePoint(60.1, 8.1),
    ], []);
    expect(trip.packingList, isNotEmpty);
    expect(trip.mealPlan, isNotNull);
    expect(repo.saved.last.route!.hasRoute, isTrue);
  });

  test(
    'meal sync keeps generated consumables and explicit user overrides',
    () async {
      final state = AppState(_MemoryRepository())
        ..profile = UserProfile(withDog: true);
      addTearDown(state.dispose);
      final trip = Trip(
        id: 'dog',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 2),
      );
      state.trips = [trip];
      state.currentTripId = trip.id;

      await state.generatePackingList(trip);
      expect(trip.packingList.map((i) => i.id), contains('dogfood'));

      await state.generateMealPlan(trip);
      expect(
        trip.packingList.map((i) => i.id),
        containsAll(['dogfood', 'food-total', 'water-total']),
      );

      await state.generatePackingList(trip);
      expect(
        trip.packingList.map((i) => i.id),
        containsAll(['dogfood', 'food-total', 'water-total']),
      );

      final food = trip.packingList.firstWhere((i) => i.id == 'food-total')
        ..packed = true
        ..unitWeightGrams = 1234
        ..weightEdited = true;
      await state.updateMealPlan(trip);
      final merged = trip.packingList.firstWhere((i) => i.id == 'food-total');
      expect(merged.packed, isTrue);
      expect(merged.unitWeightGrams, 1234);
      expect(merged.weightEdited, isTrue);
      expect(food.id, merged.id);
    },
  );

  test(
    'date changes invalidate the old forecast and resize generated plans',
    () async {
      final state = AppState(_MemoryRepository());
      addTearDown(state.dispose);
      final trip = Trip(
        id: 'dates',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 1),
      );
      state.trips = [trip];
      trip.packingList = PackingEngine().generate(trip);
      trip.mealPlan = MealPlanner.generate(trip);
      trip.weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: DateTime.now(),
      );
      trip.endDate = DateTime(2026, 7, 3);
      await state.reanalyze(trip, datesChanged: true);
      expect(trip.weather, isEmpty);
      expect(trip.mealPlan!.days, 3);
      expect(trip.mealPlan!.meals.any((meal) => meal.day == 3), isTrue);
    },
  );
}
