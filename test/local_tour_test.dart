import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:norgeskompasset/core/geo.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/models/catalog_trip.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/profile.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:norgeskompasset/screens/find_tours_screen.dart';
import 'package:norgeskompasset/screens/trips_screen.dart';
import 'package:norgeskompasset/services/local_tour_catalog.dart';
import 'package:norgeskompasset/services/meal_planner.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/trip_repository.dart';
import 'package:norgeskompasset/state/app_state.dart';
import 'package:norgeskompasset/widgets/local_tour_suggestions.dart';

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
    expect(find.text('Finn tur'), findsOneWidget);
    expect(find.text('Sognsvann – Ullevålseter'), findsOneWidget);
    expect(find.text('Besseggen'), findsNothing);
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
      route: localTours.first.previewRoute(),
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
        route: localTours.first.previewRoute(),
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

  testWidgets(
    'new trip remains available when the list filter has no matches',
    (tester) async {
      final state = AppState(_MemoryRepository())
        ..trips = [Trip(id: 'one', name: 'Nordmarka')];
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: TripsScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Ingen treff');
      await tester.pumpAndSettle();
      expect(
        find.text('Ingen turer matcher søket eller filteret.'),
        findsOneWidget,
      );
      expect(find.text('Ny tur'), findsOneWidget);
      await tester.tap(find.text('Nullstill søk og filter'));
      await tester.pumpAndSettle();
      expect(find.text('Nordmarka'), findsOneWidget);
    },
  );

  testWidgets('default suggestions show only three Nordmarka day ideas', (
    tester,
  ) async {
    final state = AppState(_MemoryRepository());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocalTourSuggestions(
                query: '',
                onRequestLocation: () {},
                onPreview: (_) {},
                onImported: (_) => fail('Browsing must not import'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Sognsvann – Ullevålseter'), findsOneWidget);
    expect(find.text('Frognerseteren – Ullevålseter'), findsOneWidget);
    expect(find.text('Vettakollen utsiktspunkt'), findsOneWidget);
    expect(find.text('Besseggen'), findsNothing);
    expect(find.text('Femunden nord til sør'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(state.trips, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test(
    'local templates have unique IDs, coordinates and explicit limitations',
    () {
      expect(localTours.length, 13);
      expect(localTours.map((tour) => tour.id).toSet().length, 13);
      for (final tour in localTours) {
        expect(tour.stops.length, greaterThanOrEqualTo(2));
        expect(tour.warning, isNotEmpty);
        expect(tour.months, isNotEmpty);
        final route = tour.previewRoute();
        expect(route.source, RouteSource.estimated);
        expect(route.distanceMeters, routeDistanceMeters(route.points));
        expect(route.points.every((point) => point.elevation == null), isTrue);
        expect(route.highestPoint, isNull);
        expect(route.totalAscent, 0);
        expect(
          route.polylineSegments().every((segment) => segment.straight),
          isTrue,
        );
        for (final stop in tour.stops) {
          expect(stop.lat, inInclusiveRange(58, 72));
          expect(stop.lon, inInclusiveRange(4, 32));
        }
      }
    },
  );

  test('search works by name, region, municipality and activity', () {
    expect(
      localTours.where((tour) => tour.matchesQuery(' jotunheimen ')).length,
      5,
    );
    expect(
      localTours.where((tour) => tour.matchesQuery('nordmarka')).length,
      5,
    );
    expect(
      localTours.where((tour) => tour.matchesQuery('GRAN')).single.id,
      'local-fjorda-kano',
    );
    expect(localTours.where((tour) => tour.matchesQuery('ski')).length, 2);
    expect(
      localTours.where((tour) => tour.matchesQuery('oslo')).length,
      greaterThanOrEqualTo(4),
    );
    expect(localTours.where((tour) => tour.matchesQuery('ukjent')), isEmpty);
  });

  test(
    'return route is explicit and previews never mutate local definitions',
    () {
      final tour = localTours.first;
      final first = tour.previewRoute();
      expect(first.points.length, 5);
      expect(first.points.first.latLng, first.points.last.latLng);
      first.waypoints.first.lat = 0;
      first.points.first.elevation = 500;
      final second = tour.previewRoute();
      expect(second.waypoints.first.lat, tour.stops.first.lat);
      expect(second.points.first.elevation, isNull);
      expect(tour.stops.length, 3);
    },
  );

  test('day count survives date boundaries and data roundtrip without promoting claimed stats', () {
    final tour = localTours.first;
    final trip = tour.createDraft(
      tripId: 'draft',
      startDate: DateTime(2026, 3, 28),
      days: 4,
      participants: 2,
      accommodation: AccommodationType.tent,
    );
    final copy = Trip.decode(trip.encode());
    expect(copy.hikingDays, 4);
    expect(copy.participants, 2);
    expect(copy.status, TripStatus.draft);
    expect(copy.localTourId, tour.id);
    expect(Trip.fromJson({'id': 'legacy'}).localTourId, isNull);
    expect(copy.route!.source, RouteSource.estimated);
    expect(copy.notes, contains(tour.provenance));
    expect(copy.notes, contains('650 m'));
    expect(copy.route!.totalAscent, 0);
    expect(
      () => tour.createDraft(
        tripId: 'bad',
        startDate: DateTime(2026),
        days: 0,
        participants: 1,
        accommodation: AccommodationType.tent,
      ),
      throwsArgumentError,
    );
  });

  test('confirmed imports use ski+pulk and canoe rules, create meals and persist only selected trips', () async {
    final repo = _MemoryRepository();
    final state = AppState(repo);
    addTearDown(state.dispose);
    for (final id in ['local-femunden-pulk', 'local-fjorda-kano']) {
      final tour = localTours.firstWhere((tour) => tour.id == id);
      final trip = await state.startFromLocalTour(
        tour,
        startDate: DateTime(2026, 7, 1),
        days: tour.durationDays,
        participants: 2,
        accommodation: tour.accommodation,
        acknowledgedUnverified: true,
      );
      expect(trip.activity, tour.activity);
      expect(trip.carry, tour.carry);
      expect(trip.season, tour.season);
      expect(trip.hikingDays, tour.durationDays);
      expect(trip.packingList, isNotEmpty);
      expect(trip.mealPlan!.days, tour.durationDays);
      expect(trip.route!.source, RouteSource.estimated);
      expect(trip.weather, isEmpty);
      expect(trip.status, TripStatus.draft);
      expect(
        trip.recommendations.any(
          (r) => r.title == 'Turmalen er ikke kontrollert',
        ),
        isTrue,
      );
      final gear = trip.packingList
          .map((item) => item.name.toLowerCase())
          .join(' ');
      if (tour.carry == CarryMode.pulk) expect(gear, contains('pulk'));
      if (tour.activity == TripActivity.paddle) {
        expect(gear, contains('flytevest'));
        expect(gear, isNot(contains('skismøring')));
      }
    }
    expect(repo.saved.length, 2);
    expect(state.trips.length, 2);
  });

  test(
    'unacknowledged or failed imports do not change the selected trip',
    () async {
      final repo = _MemoryRepository();
      final state = AppState(repo)
        ..trips = [Trip(id: 'existing')]
        ..currentTripId = 'existing';
      addTearDown(state.dispose);
      Future<Trip> import(bool acknowledge) => state.startFromLocalTour(
        localTours.first,
        startDate: DateTime(2026, 7, 1),
        days: 1,
        participants: 1,
        accommodation: AccommodationType.dayHike,
        acknowledgedUnverified: acknowledge,
      );
      await expectLater(import(false), throwsArgumentError);
      expect(repo.saved, isEmpty);
      repo.fail = true;
      await expectLater(import(true), throwsStateError);
      expect(state.trips.length, 1);
      expect(state.currentTripId, 'existing');
    },
  );

  test(
    'unverified origin warning survives regeneration and notes changes',
    () async {
      final state = AppState(_MemoryRepository());
      addTearDown(state.dispose);
      final trip = await state.startFromLocalTour(
        localTours.first,
        startDate: DateTime(2026, 7, 1),
        days: 1,
        participants: 1,
        accommodation: AccommodationType.dayHike,
        acknowledgedUnverified: true,
        season: TripSeason.winter,
      );
      trip.notes = '';
      await state.generatePackingList(trip);
      expect(trip.season, TripSeason.winter);
      expect(
        trip.recommendations.any(
          (r) => r.title == 'Turmalen er ikke kontrollert',
        ),
        isTrue,
      );
      expect(Trip.decode(trip.encode()).localTourId, localTours.first.id);
    },
  );

  testWidgets(
    'date and acknowledgement are required before one confirmed import',
    (tester) async {
      final repo = _MemoryRepository();
      final state = AppState(repo);
      Trip? imported;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LocalTourSuggestions(
                  query: 'Besseggen',
                  simpleOnly: false,
                  onRequestLocation: () {},
                  onPreview: (_) {},
                  onImported: (trip) => imported = trip,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Besseggen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Velg startdato'));
      await tester.tap(find.text('Velg startdato'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(
        FilledButton,
        'Opprett utkast og foreløpig pakkeliste',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(imported?.name, 'Besseggen');
      expect(repo.saved.length, 1);
      expect(state.trips.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cards preview without creating trips and cancellation leaves state unchanged',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _MemoryRepository();
      final state = AppState(repo);
      HikingRoute? preview;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LocalTourSuggestions(
                  query: '',
                  simpleOnly: false,
                  onRequestLocation: () {},
                  onPreview: (route) => preview = route,
                  onImported: (_) => fail('Preview must not import'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Galdhøpiggen fra Juvasshytta'), findsOneWidget);
      await tester.tap(find.text('Galdhøpiggen fra Juvasshytta'));
      await tester.pumpAndSettle();
      expect(preview!.source, RouteSource.estimated);
      expect(find.text(localTours.first.provenance), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(
          FilledButton,
          'Opprett utkast og foreløpig pakkeliste',
        ),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.text('Avbryt'));
      await tester.pumpAndSettle();
      expect(state.trips, isEmpty);
      expect(repo.saved, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
