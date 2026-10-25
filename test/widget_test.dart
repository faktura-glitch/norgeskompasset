import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:norgeskompasset/models/meal.dart';
import 'package:norgeskompasset/screens/safety_screen.dart';
import 'package:norgeskompasset/screens/more_screen.dart';
import 'package:norgeskompasset/screens/packing_screen.dart';
import 'package:norgeskompasset/screens/trips_screen.dart';
import 'package:norgeskompasset/services/trip_repository.dart';
import 'package:norgeskompasset/state/app_state.dart';
import 'package:latlong2/latlong.dart';
import 'package:norgeskompasset/core/energy.dart';
import 'package:norgeskompasset/core/geo.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/profile.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/stage.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/gpx_service.dart';
import 'package:norgeskompasset/services/recommendation_engine.dart';
import 'package:norgeskompasset/services/meal_planner.dart';
import 'package:norgeskompasset/services/food_menu_catalog.dart';
import 'package:norgeskompasset/models/gear.dart';
import 'package:norgeskompasset/services/gear_catalog.dart';
import 'package:norgeskompasset/services/trip_analysis.dart';
import 'package:norgeskompasset/models/weather.dart';

void main() {
  group('UX persistence', () {
    test('activity changes immediately refresh estimated duration', () async {
      final trip = Trip(id: 'activity')
        ..route = HikingRoute(
          points: [RoutePoint(60, 8), RoutePoint(60.05, 8)],
          distanceMeters: 5500,
        );
      final state = AppState(TripRepository());
      await state.updateTripSetup(trip);
      final walking = trip.totalEstimatedMinutes;
      trip.activity = TripActivity.bike;
      await state.updateTripSetup(trip);
      expect(trip.totalEstimatedMinutes, greaterThan(0));
      expect(trip.totalEstimatedMinutes, lessThan(walking));
    });
    testWidgets('packing search resets on a narrow screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final trip = Trip(id: 'p', name: 'Mobiltest')
        ..packingList = [
          PackingItem(
            id: '1',
            name: 'Lue',
            category: PackingCategory.additional,
            unitWeightGrams: 100,
          ),
        ];
      final state = AppState(TripRepository())
        ..trips = [trip]
        ..currentTripId = trip.id;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: PackingScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'finnes ikke');
      await tester.pump();
      await tester.tap(find.text('Nullstill filtre'));
      await tester.pump();
      expect(find.text('Lue'), findsOneWidget);
      expect(find.text('finnes ikke'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('trip status filters show only matching trips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState(TripRepository())
        ..trips = [
          Trip(id: 'a', name: 'Ny tur'),
          Trip(id: 'b', name: 'Gammel tur')..status = TripStatus.completed,
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: TripsScreen()),
        ),
      );
      await tester.tap(find.text('Fullførte'));
      await tester.pump();
      expect(find.text('Gammel tur'), findsOneWidget);
      expect(find.text('Ny tur', skipOffstage: true), findsOneWidget);
      expect(find.text('Utkast'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    test('regeneration preserves own gear and acquisition state', () {
      final trip = Trip(id: 'custom')
        ..packingList = [
          PackingItem(
            id: 'custom',
            name: 'Min spesielle kikkert',
            category: PackingCategory.additional,
            userAdded: true,
            needsAcquisition: true,
            worn: true,
          ),
        ];
      final items = PackingEngine().generate(trip);
      final custom = items.singleWhere(
        (i) => i.name == 'Min spesielle kikkert',
      );
      expect(custom.needsAcquisition, isTrue);
      expect(custom.worn, isTrue);
      final restored = PackingItem.fromJson(custom.toJson());
      expect(restored.copy().needsAcquisition, isTrue);
    });
    test('shopping checks and edited meals survive storage', () {
      final meal = PlannedMeal(
        id: 'm',
        day: 1,
        type: MealType.lunch,
        name: 'Egen lunsj',
        gramsPerPerson: 200,
        userEdited: true,
      );
      final plan = MealPlan(meals: [meal]);
      plan.checkedShoppingItems.add(plan.shoppingList.single);
      final restored = MealPlan.fromJson(plan.toJson());
      expect(
        restored.checkedShoppingItems,
        contains(restored.shoppingList.single),
      );
      expect(restored.meals.single.userEdited, isTrue);
    });
    test('old meal plans get independent mutable shopping checks', () {
      final first = MealPlan.fromJson({});
      final second = MealPlan.fromJson({});
      first.checkedShoppingItems.add('mat');
      expect(second.checkedShoppingItems, isEmpty);
      expect(PlannedMeal.fromJson({'id': 'old'}).userEdited, isFalse);
    });
    test('worn equipment does not affect pack completion', () {
      final trip = Trip(id: 'pack')
        ..packingList = [
          PackingItem(
            id: 'boots',
            name: 'Støvler',
            category: PackingCategory.additional,
            unitWeightGrams: 2000,
            worn: true,
          ),
          PackingItem(
            id: 'food',
            name: 'Mat',
            category: PackingCategory.food,
            unitWeightGrams: 500,
            packed: true,
          ),
        ];
      expect(trip.packingCompletion, 1);
    });
    testWidgets('emergency information is available without a selected trip', (
      tester,
    ) async {
      final state = AppState(TripRepository());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: SafetyScreen(emergencyFirst: true)),
        ),
      );
      expect(find.text('Nødnumre i Norge'), findsOneWidget);
      expect(find.text('Vis min posisjon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('safety screen renders the active trip plan', (tester) async {
      final trip = Trip(id: 'safety', name: 'Jotunheimen')
        ..route = HikingRoute(
          points: [RoutePoint(61.5, 8.5), RoutePoint(61.56, 8.6)],
          waypoints: [
            Waypoint(
              id: 'start',
              name: 'Gjendesheim',
              lat: 61.5,
              lon: 8.5,
              type: WaypointType.start,
            ),
            Waypoint(
              id: 'end',
              name: 'Memurubu',
              lat: 61.56,
              lon: 8.6,
              type: WaypointType.end,
            ),
          ],
          source: RouteSource.trail,
          distanceMeters: 8500,
        );
      final state = AppState(TripRepository())
        ..trips = [trip]
        ..currentTripId = trip.id;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: SafetyScreen()),
        ),
      );
      expect(find.text('Turkort for trygge kontakter'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Offline kart'), 300);
      expect(find.text('Offline kart'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Innsjekking og retur'), 300);
      expect(find.text('Innsjekking og retur'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('profile opens as a page with explicit save', (tester) async {
      final state = AppState(TripRepository());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: MoreScreen()),
        ),
      );
      await tester.scrollUntilVisible(find.text('Min profil'), 250);
      await tester.tap(find.text('Min profil'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Min profil'), findsOneWidget);
      expect(find.text('Lagre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  group('Geo & elevation math', () {
    test('route distance accumulates correctly', () {
      // ~111.19 km per degree latitude.
      final points = [
        RoutePoint(60.0, 8.0),
        RoutePoint(60.5, 8.0),
        RoutePoint(61.0, 8.0),
      ];
      final d = routeDistanceMeters(points);
      expect(d, greaterThan(100000));
      expect(d, lessThan(120000));
    });

    test('track simplification drops noise but keeps real turns', () {
      // 200-point line northbound with ~5 m zig-zag noise — inside
      // the 50 m tolerance, so almost everything is dropped.
      final raw = <LatLng>[
        for (var i = 0; i <= 200; i++)
          LatLng(60.0 + i * 0.001, 8.0 + (i.isOdd ? 0.0001 : -0.0001)),
      ];
      final simplified = simplifyPolyline(raw, 50, (p) => p);
      expect(simplified.length, lessThan(raw.length ~/ 4));
      expect(simplified.first.latitude, raw.first.latitude);
      expect(simplified.last.latitude, raw.last.latitude);

      // A genuine ~1 km detour must survive the same tolerance.
      final withDetour = List<LatLng>.of(raw);
      withDetour[100] = LatLng(60.1, 8.03);
      final kept = simplifyPolyline(withDetour, 50, (p) => p);
      expect(kept.any((p) => p.longitude == 8.03), isTrue);
    });

    test('ascent/descent ignore small noise', () {
      final points = [
        RoutePoint(60.0, 8.0, elevation: 1000),
        RoutePoint(60.01, 8.0, elevation: 1001), // noise
        RoutePoint(60.02, 8.0, elevation: 1100),
        RoutePoint(60.03, 8.0, elevation: 1102), // noise
        RoutePoint(60.04, 8.0, elevation: 900),
      ];
      final s = elevationStats(points);
      expect(s.ascent, greaterThan(90));
      expect(s.ascent, lessThan(120));
      expect(s.descent, greaterThan(190));
      expect(s.descent, lessThan(230));
      expect(s.highest, 1102);
    });

    test('missing elevations are skipped safely', () {
      final points = [
        RoutePoint(60.0, 8.0, elevation: 1000),
        RoutePoint(60.01, 8.0),
        RoutePoint(60.02, 8.0, elevation: 1200),
      ];
      final s = elevationStats(points);
      expect(s.ascent, 200);
    });

    test('stage split covers the whole route', () {
      final points = List.generate(
        100,
        (i) => RoutePoint(60.0 + i * 0.001, 8.0),
      );
      final splits = splitIntoStages(points, 4);
      expect(splits.length, 4);
      // Boundaries are shared between consecutive stages.
      for (var i = 1; i < splits.length; i++) {
        expect(splits[i].first.lat, splits[i - 1].last.lat);
      }
      expect(splits.first.first.lat, points.first.lat);
      expect(splits.last.last.lat, points.last.lat);
    });

    test('Naismith time scales with distance and ascent', () {
      final flat = estimateHikingMinutes(10000, 0, 0, HikingPace.normal);
      final hilly = estimateHikingMinutes(10000, 800, 0, HikingPace.normal);
      expect(flat, closeTo(120, 1));
      expect(hilly, greaterThan(flat));
      final brisk = estimateHikingMinutes(10000, 0, 0, HikingPace.brisk);
      expect(brisk, lessThan(flat));
    });

    test('difficulty increases with ascent', () {
      Stage mk(double km, double asc) {
        final pts = List.generate(
          20,
          (i) => RoutePoint(60.0 + i * 0.001, 8.0, elevation: i * asc / 19),
        );
        return Stage(
          id: 'x',
          number: 1,
          points: pts,
          distanceMeters: km * 1000,
          ascent: asc,
          estimatedMinutes: km * 20,
        );
      }

      final easy = analyzeStageDifficulty(mk(5, 50));
      final hard = analyzeStageDifficulty(mk(20, 1500));
      expect(easy.score, lessThan(hard.score));
      expect(easy.level.index, lessThan(hard.level.index));
      expect(hard.factors, isNotEmpty);
    });

    test('nearest point finds closest index', () {
      final points = List.generate(10, (i) => RoutePoint(60.0 + i * 0.01, 8.0));
      final idx = nearestPointIndex(points, const LatLng(60.044, 8.0));
      expect(idx, 4);
    });
  });

  group('Packing engine', () {
    Trip trip({AccommodationType acc = AccommodationType.tent, int days = 3}) {
      final t = Trip(id: 't1', accommodation: acc);
      t.startDate = DateTime(2026, 7, 1);
      t.endDate = t.startDate!.add(Duration(days: days - 1));
      return t;
    }

    test('generates required safety items', () {
      final items = PackingEngine().generate(trip());
      bool has(String n) => items.any((i) => i.name.toLowerCase().contains(n));
      expect(has('kart'), isTrue);
      expect(has('kompass'), isTrue);
      expect(has('førstehjelp'), isTrue);
      expect(has('vindsekk'), isTrue);
      expect(has('telt'), isTrue);
    });

    test('day trip omits tent and sleeping gear', () {
      final items = PackingEngine().generate(
        trip(acc: AccommodationType.dayHike, days: 1),
      );
      expect(items.any((i) => i.name.contains('Telt')), isFalse);
      expect(items.any((i) => i.name.contains('Sovepose')), isFalse);
    });

    test('cabin trip adds hut sheet but no tent', () {
      final items = PackingEngine().generate(
        trip(acc: AccommodationType.cabin),
      );
      expect(items.any((i) => i.name.contains('Telt')), isFalse);
      expect(items.any((i) => i.name.toLowerCase().contains('laken')), isTrue);
    });

    test('optimize never removes required items', () {
      final t = trip();
      t.packingList = PackingEngine().generate(t);
      final before = t.packingList.length;
      final removed = PackingEngine().optimize(t);
      expect(t.packingList.length, before - removed);
      expect(t.packingList.any((i) => i.name.contains('Kompass')), isTrue);
    });

    test('learns missing items from past reviews', () {
      final old = trip()..name = 'Jotunheimen';
      old.review = TripReview(missing: ['Solbriller', 'Gaiters']);
      final items = PackingEngine().generate(trip(), pastTrips: [old]);
      expect(items.any((i) => i.name == 'Solbriller'), isTrue);
      expect(items.any((i) => i.name == 'Gaiters'), isTrue);
      // Required items marked unnecessary are kept anyway.
      old.review = TripReview(unnecessary: ['Kompass']);
      final items2 = PackingEngine().generate(trip(), pastTrips: [old]);
      expect(items2.any((i) => i.name.contains('Kompass')), isTrue);
    });

    test('per-person items scale with participants', () {
      final t = trip()..participants = 3;
      final items = PackingEngine().generate(t);
      PackingItem find(String n) => items.firstWhere((i) => i.name.contains(n));
      // Per-person: socks are 3 pairs × 3 participants.
      expect(find('Ullsokker').quantity, 9);
      expect(find('Sovepose').quantity, 3);
      expect(find('Hodelykt').quantity, 3);
      expect(find('Nødproviant').quantity, 3);
      // Shared gear stays at 1 regardless of group size.
      expect(find('Telt').quantity, 1);
      expect(find('Førstehjelp').quantity, 1);
      expect(find('Kompass').quantity, 1);
    });

    test('winter adds avalanche gear and forces cold items', () {
      final t = trip()..season = TripSeason.winter;
      final items = PackingEngine().generate(t);
      bool has(String n) => items.any((i) => i.name.toLowerCase().contains(n));
      expect(has('skredsøker'), isTrue);
      expect(has('skredspade'), isTrue);
      expect(has('søkestang'), isTrue);
      expect(has('truger'), isTrue);
      // Winter forces cold assumptions even without a forecast.
      expect(
        items.firstWhere((i) => i.name.contains('Varmeputer')).priority,
        isNotNull,
      );
    });

    test('pulk replaces the backpack', () {
      final t = trip()..carry = CarryMode.pulk;
      final items = PackingEngine().generate(t);
      expect(items.any((i) => i.name.contains('Pulk')), isTrue);
      expect(items.any((i) => i.name.contains('trekksele')), isTrue);
      // Dry bags are mandatory per pulk-packing guides.
      expect(items.any((i) => i.name.contains('pakkposer')), isTrue);
      expect(items.any((i) => i.name.contains('Dagssekk')), isFalse);
      // Backpack mode gets the pack instead.
      final pack = PackingEngine().generate(trip());
      expect(pack.any((i) => i.name.contains('Sekk')), isTrue);
    });

    test('canoe adds water-safety gear, no backpack', () {
      final t = trip()..carry = CarryMode.canoe;
      final items = PackingEngine().generate(t);
      bool has(String n) => items.any((i) => i.name.toLowerCase().contains(n));
      expect(has('flytevest'), isTrue);
      expect(has('reserveåre'), isTrue);
      expect(has('pakksekker'), isTrue);
      expect(has('kartmappe'), isTrue);
      expect(has('sekk 50'), isFalse);
    });

    test('autumn adds hi-vis, spring adds gaiters', () {
      final autumnItems = PackingEngine().generate(
        trip()..season = TripSeason.autumn,
      );
      expect(autumnItems.any((i) => i.name.contains('Signalplagg')), isTrue);
      final springItems = PackingEngine().generate(
        trip()..season = TripSeason.spring,
      );
      expect(springItems.any((i) => i.name.contains('Gamasjer')), isTrue);
    });

    test('cold-sensitive profile adds an extra warm layer', () {
      final profile = UserProfile(coldSensitive: true);
      final items = PackingEngine().generate(trip(), profile: profile);
      expect(items.any((i) => i.name.contains('Ekstra varmeplagg')), isTrue);
      // Without the profile the item is absent.
      final plain = PackingEngine().generate(trip());
      expect(plain.any((i) => i.name.contains('Ekstra varmeplagg')), isFalse);
    });

    test('marks unnecessary items without removing them', () {
      final old = trip()..review = TripReview(unnecessary: ['Kamera']);
      final items = PackingEngine().generate(trip(), pastTrips: [old]);
      final cam = items.firstWhere((i) => i.name.contains('Kamera'));
      // Still present, but flagged via its reason.
      expect(cam.reason!.contains('unødvendig'), isTrue);
    });
  });

  group('Packing rule matrix', () {
    TripConditions cond({
      TripActivity activity = TripActivity.foot,
      CarryMode carry = CarryMode.backpack,
      AccommodationType acc = AccommodationType.tent,
      TripSeason season = TripSeason.summer,
      int days = 3,
      double? minTemp,
      AvalancheRisk avalanche = AvalancheRisk.none,
      bool withDog = false,
    }) => TripConditions(
      activity: activity,
      carry: carry,
      accommodation: acc,
      season: season,
      days: days,
      people: 1,
      minTemp: minTemp,
      avalanche: avalanche,
      withDog: withDog,
    );

    List<GearItem> matching(TripConditions c) =>
        gearCatalog.where((g) => g.matches(c)).toList();

    bool skiGear(GearItem i) =>
        const {'ski', 'skiboots', 'skistaves', 'wax', 'skins'}.contains(i.id);

    test('foot + pulk never pulls in ski gear', () {
      final items = matching(
        cond(
          carry: CarryMode.pulk,
          season: TripSeason.winter,
          avalanche: AvalancheRisk.uncertain,
        ),
      );
      expect(items.any(skiGear), isFalse);
      expect(items.any((i) => i.name.contains('Pulk')), isTrue);
      expect(items.any((i) => i.name.contains('Truger')), isTrue);
    });

    test('canoe always carries flotation and excludes land gear', () {
      final items = matching(cond(carry: CarryMode.canoe));
      expect(items.any((i) => i.name.contains('Flytevest')), isTrue);
      expect(items.any((i) => i.name.contains('Reserveåre')), isTrue);
      expect(items.any((i) => i.name.contains('Ski')), isFalse);
      expect(items.any((i) => i.name.contains('Sekk')), isFalse);
    });

    test('bike never pulls ski or paddle gear', () {
      final items = matching(cond(activity: TripActivity.bike));
      expect(items.any(skiGear), isFalse);
      expect(items.any((i) => i.name.contains('Reserveåre')), isFalse);
      expect(items.any((i) => i.name.contains('Padleåre')), isFalse);
      expect(items.any((i) => i.name.contains('Sykkelhjelm')), isTrue);
    });

    test('day trip excludes all overnight gear', () {
      final items = matching(cond(acc: AccommodationType.dayHike, days: 1));
      final names = items.map((i) => i.name.toLowerCase()).join('|');
      expect(names.contains('telt'), isFalse);
      expect(names.contains('sovepose'), isFalse);
      expect(names.contains('liggeunderlag'), isFalse);
      expect(names.contains('brenner'), isFalse);
    });

    test('cabin and tent produce different modules', () {
      final tent = matching(cond(acc: AccommodationType.tent));
      final cabin = matching(cond(acc: AccommodationType.cabin));
      expect(tent.any((i) => i.name.contains('Telt')), isTrue);
      expect(cabin.any((i) => i.name.contains('Telt')), isFalse);
      expect(cabin.any((i) => i.name.contains('Lakenpose')), isTrue);
      expect(tent.any((i) => i.name.contains('Lakenpose')), isFalse);
    });

    test('unknown temperature is not treated as warm', () {
      final items = matching(cond(minTemp: null));
      // Cold-gated gear stays (conservative), warm-gated gear leaves.
      expect(items.any((i) => i.name.contains('Dun-/fiberjakke')), isTrue);
      final winterItems = matching(
        cond(minTemp: null, season: TripSeason.winter),
      );
      expect(winterItems.any((i) => i.name.contains('Solhatt')), isFalse);
    });

    test('warm forecast drops the down jacket for cycling only', () {
      final bike = matching(cond(activity: TripActivity.bike, minTemp: 20));
      expect(bike.any((i) => i.name.contains('Dun-/fiberjakke')), isFalse);
      final foot = matching(cond(minTemp: 20));
      expect(foot.any((i) => i.name.contains('Dun-/fiberjakke')), isTrue);
    });

    test('avalanche gear follows terrain risk, not season', () {
      // Unknown terrain in winter → gear included with a caveat.
      final uncertain = matching(
        cond(season: TripSeason.winter, avalanche: AvalancheRisk.uncertain),
      );
      expect(
        uncertain.any((i) => i.name.toLowerCase().contains('skredsøker')),
        isTrue,
      );
      // Confirmed safe → gear left out.
      final noRisk = matching(cond(season: TripSeason.winter));
      expect(
        noRisk.any((i) => i.name.toLowerCase().contains('skredsøker')),
        isFalse,
      );
      final confirmed = matching(cond(avalanche: AvalancheRisk.yes));
      expect(confirmed.any((i) => i.name.contains('Søkestang')), isTrue);
    });

    test('dog gear only appears when the dog comes along', () {
      final without = matching(cond());
      expect(without.any((i) => i.name.contains('Hund')), isFalse);
      final withDog = matching(cond(withDog: true));
      expect(withDog.any((i) => i.name.contains('Hundeskål')), isTrue);
      expect(withDog.any((i) => i.name.contains('Hundemat')), isTrue);
      final klov = withDog.firstWhere((i) => i.name.contains('Hundekløv'));
      expect(klov.priority, PackingPriority.optional);
    });

    test('presets select parameters, not opaque lists', () {
      final footPulk = packingPresets.firstWhere((p) => p.id == 'foot-pulk');
      final t = Trip(id: 'preset');
      footPulk.apply(t);
      expect(t.activity, TripActivity.foot);
      expect(t.carry, CarryMode.pulk);
      final items = PackingEngine().generate(t);
      final names = items.map((i) => i.name).join('|');
      for (final n in ['Skisko', 'Skistaver', 'Skismøring', 'skifeller']) {
        expect(names.contains(n), isFalse);
      }
      final canoe = packingPresets.firstWhere((p) => p.id == 'canoe');
      canoe.apply(t);
      final canoeItems = PackingEngine().generate(t);
      expect(canoeItems.any((i) => i.name.contains('Flytevest')), isTrue);
    });

    test('consumables are separated from base weight', () {
      final t = Trip(id: 'w', accommodation: AccommodationType.tent)
        ..startDate = DateTime(2026, 7, 1)
        ..endDate = DateTime(2026, 7, 3);
      final items = PackingEngine().generate(t);
      final base = items
          .where((i) => !i.isConsumable && !i.worn)
          .fold(0.0, (s, i) => s + i.totalWeightGrams);
      final consum = items
          .where((i) => i.isConsumable)
          .fold(0.0, (s, i) => s + i.totalWeightGrams);
      expect(base, greaterThan(0));
      expect(consum, greaterThan(0)); // fuel, food, hygiene
      expect(
        items.firstWhere((i) => i.name.contains('Gass/brensel')).isConsumable,
        isTrue,
      );
      expect(
        items.firstWhere((i) => i.name.contains('Telt')).isConsumable,
        isFalse,
      );
    });
  });

  group('Meal planner', () {
    test('scales with days and people', () {
      final t = Trip(id: 't');
      t.startDate = DateTime(2026, 7, 1);
      t.endDate = DateTime(2026, 7, 3);
      t.participants = 2;
      final plan = MealPlanner.generate(t);
      expect(plan.days, 3);
      expect(plan.meals.where((m) => m.day == 2), isNotEmpty);
      expect(plan.totalFoodWeightGrams, greaterThan(0));
      final shopping = plan.shoppingList;
      expect(shopping, isNotEmpty);
    });
  });

  group('Food menus', () {
    Trip trip({int people = 1}) {
      final t = Trip(id: 'menu')..participants = people;
      t.startDate = DateTime(2026, 7, 1);
      t.endDate = DateTime(2026, 7, 3);
      return t;
    }

    test('catalog has 35 unique menus with sane totals', () {
      expect(foodMenus.length, 35);
      expect(foodMenus.map((m) => m.id).toSet().length, 35);
      for (final menu in foodMenus) {
        expect(menu.meals, isNotEmpty);
        expect(menu.totalWeightGrams, greaterThan(0));
        expect(menu.totalCalories, greaterThan(0));
        expect(menu.tags, isNotEmpty);
        expect(foodMenuById(menu.id), same(menu));
      }
    });

    test('applying a menu to one day keeps the other days', () {
      final t = trip();
      t.mealPlan = MealPlanner.generate(t);
      final day1Before = t.mealPlan!.meals.where((m) => m.day == 1).toList();
      final menu = foodMenuById('menu13')!;
      final plan = MealPlanner.applyMenu(t, menu, day: 2);
      // Day 2 is replaced by the menu.
      expect(
        plan.meals.where((m) => m.day == 2).map((m) => m.sourceMenuId).toSet(),
        {'menu13'},
      );
      // Day 1 is untouched.
      expect(
        plan.meals.where((m) => m.day == 1).map((m) => m.name).toList(),
        day1Before.map((m) => m.name).toList(),
      );
      // Menu kcal and weight land in the plan.
      expect(plan.kcalPerPersonDay(2), closeTo(menu.totalCalories, 1));
      expect(plan.days, 3);
    });

    test('applying a menu to all days scales kcal and grams per person', () {
      final t = trip(people: 2);
      final menu = foodMenuById('menu01')!;
      final plan = MealPlanner.applyMenu(t, menu);
      expect(plan.meals.length, menu.meals.length * 3);
      for (var day = 1; day <= 3; day++) {
        expect(plan.kcalPerPersonDay(day), closeTo(menu.totalCalories, 1));
      }
      expect(
        plan.totalFoodWeightGrams,
        closeTo(menu.totalWeightGrams * 3 * 2, 1),
      );
    });

    test('dietary conflicts block application without unsafe claims', () {
      final t = trip();
      final meat = foodMenuById('menu01')!;
      expect(
        () => MealPlanner.applyMenu(
          t,
          meat,
          profile: UserProfile(vegetarian: true),
        ),
        throwsArgumentError,
      );
      final vegan = foodMenuById('menu13')!;
      final plan = MealPlanner.applyMenu(
        t,
        vegan,
        profile: UserProfile(vegetarian: true),
      );
      expect(plan.meals, isNotEmpty);
      // Nut allergy surfaces menus carrying nuts/peanuts.
      final nutProfile = UserProfile(nutAllergy: true);
      expect(meat.conflictsWith(nutProfile, const []), isNotEmpty);
    });

    test('kept shopping checks survive a menu switch', () {
      final t = trip();
      t.mealPlan = MealPlanner.generate(t);
      final kept = t.mealPlan!.meals.firstWhere((m) => m.day == 1);
      t.mealPlan!.checkedShoppingItems.add(
        t.mealPlan!.shoppingList.firstWhere((s) => s.contains(kept.name)),
      );
      final plan = MealPlanner.applyMenu(t, foodMenuById('menu05')!, day: 2);
      expect(plan.checkedShoppingItems, hasLength(1));
      expect(plan.checkedShoppingItems.single, contains(kept.name));
    });

    test('invalid day or empty trip is rejected', () {
      expect(
        () => MealPlanner.applyMenu(trip(), foodMenuById('menu01')!, day: 4),
        throwsArgumentError,
      );
      final empty = Trip(id: 'empty')..participants = 0;
      expect(
        () => MealPlanner.applyMenu(empty, foodMenuById('menu01')!),
        throwsArgumentError,
      );
    });
  });

  group('Energy estimate', () {
    Trip staged() {
      final t = Trip(id: 't')..participants = 1;
      t.stages = [
        Stage(
          id: 's1',
          number: 1,
          points: const [],
          distanceMeters: 15000,
          ascent: 800,
          descent: 200,
          estimatedMinutes: 400,
        ),
      ];
      return t;
    }

    test('scales with pack weight, ascent and cold', () {
      final light = estimateDailyKcal(staged(), bodyKg: 75);
      // Heavier pack via generated packing weight.
      final heavyTrip = staged()
        ..packingList = [
          PackingItem(
            id: 'x',
            name: 'Ekstra last',
            category: PackingCategory.additional,
            quantity: 1,
            unitWeightGrams: 20000,
          ),
        ];
      final heavy = estimateDailyKcal(heavyTrip, bodyKg: 75);
      expect(heavy.kcalPerDay, greaterThan(light.kcalPerDay));
      // Cold adds a supplement.
      final cold = estimateDailyKcal(staged(), bodyKg: 75, minTempC: -12);
      expect(cold.kcalPerDay, greaterThan(light.kcalPerDay));
      expect(cold.coldKcal, greaterThan(0));
      // Heavier body costs more.
      final heavier = estimateDailyKcal(staged(), bodyKg: 95);
      expect(heavier.kcalPerDay, greaterThan(light.kcalPerDay));
    });

    test('steep terrain raises the MET band', () {
      Trip withStage(double ascent, double minutes) => Trip(id: 't')
        ..participants = 1
        ..stages = [
          Stage(
            id: 's1',
            number: 1,
            points: const [],
            distanceMeters: 15000,
            ascent: ascent,
            descent: 100,
            estimatedMinutes: minutes,
          ),
        ];
      final flat = estimateDailyKcal(withStage(100, 400), bodyKg: 75);
      final steep = estimateDailyKcal(withStage(1400, 550), bodyKg: 75);
      // Same distance — the steep day must cost more, and its MET
      // band must be higher (the model's terrain signal).
      expect(steep.kcalPerDay, greaterThan(flat.kcalPerDay));
      expect(steep.avgMet, greaterThan(flat.avgMet));
      expect(steep.activityKcal, greaterThan(flat.activityKcal));
    });
  });

  group('Weather analysis & recommendations', () {
    WeatherSnapshot snapWithRain() {
      final now = DateTime.now();
      final base = DateTime(now.year, now.month, now.day, 0);
      return WeatherSnapshot(
        lat: 60.0,
        lon: 8.0,
        retrievedAt: now,
        hours: [
          for (var i = 0; i < 48; i++)
            WeatherHour(
              time: base.add(Duration(hours: i)),
              temperature: i < 30 ? 12 : -2,
              precipitationMm: i < 20 ? 2.0 : 0,
              windSpeed: i < 20 ? 14 : 3,
              cloudCover: 90,
            ),
        ],
      );
    }

    test('summarizes rain, wind and freezing correctly', () {
      final snap = snapWithRain();
      final now = DateTime.now();
      final c = TripAnalysis.summarize(
        [snap],
        DateTime(now.year, now.month, now.day, 6),
        DateTime(now.year, now.month, now.day + 1, 6),
      );
      expect(c.hasData, isTrue);
      expect(c.rainExpected, isTrue);
      expect(c.strongWind, isTrue);
      expect(c.minTemp, lessThanOrEqualTo(12));
    });

    test('recommendation engine produces linked advice', () {
      final now = DateTime.now();
      final trip = Trip(id: 't', accommodation: AccommodationType.tent);
      trip.startDate = now;
      trip.endDate = now;
      final pts = List.generate(
        10,
        (i) => RoutePoint(60.0 + i * 0.001, 8.0, elevation: 1000),
      );
      trip.route = HikingRoute(
        points: pts,
        distanceMeters: 9000,
        source: RouteSource.estimated,
      );
      final stage = Stage(
        id: 's1',
        number: 1,
        date: now,
        points: pts,
        distanceMeters: 9000,
        ascent: 400,
        estimatedMinutes: 200,
      );
      trip.stages = [stage];
      trip.weather['s1'] = snapWithRain();
      final recs = RecommendationEngine().build(trip);
      expect(recs.any((r) => r.title.toLowerCase().contains('regn')), isTrue);
      expect(recs.any((r) => r.title.toLowerCase().contains('vind')), isTrue);
      expect(
        recs.any(
          (r) =>
              r.observation.contains('estimert') ||
              r.title.contains('verifisert'),
        ),
        isTrue,
      );
      // Rain rec is tied to stage 1.
      final rain = recs.firstWhere(
        (r) => r.title.toLowerCase().contains('regn'),
      );
      expect(rain.stageNumber, 1);
    });

    test('beyond-horizon stages get honesty recommendation', () {
      final trip = Trip(id: 't');
      trip.startDate = DateTime.now().add(const Duration(days: 30));
      trip.endDate = trip.startDate;
      final stage = Stage(
        id: 's1',
        number: 1,
        date: trip.startDate,
        points: const [],
      );
      trip.stages = [stage];
      trip.weather['s1'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: DateTime.now(),
        hours: [WeatherHour(time: DateTime.now(), temperature: 10)],
      );
      final recs = RecommendationEngine().build(trip);
      expect(
        recs.any(
          (r) =>
              r.title.contains('prognose') ||
              r.observation.contains('varselhorisont'),
        ),
        isTrue,
      );
    });
  });

  group('Profile level assessment', () {
    Trip stagedTrip() {
      final t = Trip(id: 't');
      t.stages = [
        Stage(
          id: 's1',
          number: 1,
          points: const [],
          distanceMeters: 20000,
          ascent: 1200,
          descent: 100,
          estimatedMinutes: 600,
        ),
      ];
      return t;
    }

    test('novice level flags a heavy stage', () {
      final recs = RecommendationEngine().build(
        stagedTrip(),
        profile: UserProfile(level: TourLevel.novice),
      );
      expect(recs.any((r) => r.title.contains('over nivået')), isTrue);
      // Same stage is fine for an experienced hiker.
      final ok = RecommendationEngine().build(
        stagedTrip(),
        profile: UserProfile(level: TourLevel.experienced),
      );
      expect(ok.any((r) => r.title.contains('over nivået')), isFalse);
      expect(ok.any((r) => r.title.contains('innenfor nivået')), isTrue);
    });

    test('no level set means no assessment', () {
      final recs = RecommendationEngine().build(stagedTrip());
      expect(recs.any((r) => r.title.contains('nivå')), isFalse);
    });
  });

  group('GPX export', () {
    test('produces valid GPX 1.1 with wpt and trkpt', () {
      final t = Trip(id: 'g', name: 'Besseggen & omegn')
        ..route = HikingRoute(
          points: [
            RoutePoint(61.5, 8.1, elevation: 1000),
            RoutePoint(61.51, 8.11, elevation: 1100),
          ],
          waypoints: [
            Waypoint(
              id: 'w',
              name: 'Gjendesheim',
              lat: 61.5,
              lon: 8.1,
              type: WaypointType.start,
            ),
          ],
          source: RouteSource.trail,
          distanceMeters: 1400,
        );
      final gpx = GpxService.toGpx(t);
      expect(gpx, contains('<gpx version="1.1"'));
      expect(gpx, contains('Besseggen &amp; omegn'));
      expect(gpx, contains('<wpt lat="61.500000" lon="8.100000">'));
      expect(
        gpx,
        contains(
          '<trkpt lat="61.510000" lon="8.110000"><ele>1100.0</ele></trkpt>',
        ),
      );
    });

    test('parse extracts trkpt, wpt and track name', () {
      const gpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="61.5" lon="8.1"><name>Gjendesheim</name></wpt>
  <trk><name>Besseggen</name><trkseg>
    <trkpt lat="61.5" lon="8.1"><ele>1000</ele></trkpt>
    <trkpt lat="61.51" lon="8.11"><ele>1100</ele></trkpt>
    <trkpt lat="61.52" lon="8.12"/>
  </trkseg></trk>
</gpx>''';
      final r = GpxService.parse(gpx);
      expect(r.points.length, 3);
      expect(r.points[0].elevation, 1000);
      expect(r.points[2].elevation, isNull);
      expect(r.waypoints.single.name, 'Gjendesheim');
      expect(r.name, 'Besseggen');
    });

    test('parse falls back to rtept and rejects empty docs', () {
      const rte = '''<gpx version="1.1"><rte>
        <rtept lat="60.0" lon="8.0"/>
        <rtept lat="60.1" lon="8.1"/>
      </rte></gpx>''';
      expect(GpxService.parse(rte).points.length, 2);
      expect(() => GpxService.parse('<gpx></gpx>'), throwsException);
      expect(() => GpxService.parse('not xml'), throwsException);
    });
  });

  group('Off-route detection', () {
    test('distance to polyline measures perpendicular, not vertex', () {
      // A straight leg of ~2.2 km; a point mid-segment 100 m east is
      // ~100 m off route even though it is >1 km from both vertices.
      final pts = [RoutePoint(60.0, 8.0), RoutePoint(60.02, 8.0)];
      final mid = const LatLng(60.01, 8.0018); // ~100 m east
      final d = distanceToRouteMeters(pts, mid);
      expect(d, greaterThan(80));
      expect(d, lessThan(120));
    });

    test('on-route position reports small distance', () {
      final pts = [RoutePoint(60.0, 8.0), RoutePoint(60.02, 8.0)];
      expect(distanceToRouteMeters(pts, const LatLng(60.01, 8.0)), lessThan(5));
      // Beyond the segment end -> distance to the end point.
      final d = distanceToRouteMeters(pts, const LatLng(60.03, 8.0));
      expect(d, greaterThan(1000));
    });
  });

  group('Trip serialization', () {
    test('round-trip preserves data', () {
      final t = Trip(id: 'abc', name: 'Testtur')
        ..startDate = DateTime(2026, 7, 10)
        ..endDate = DateTime(2026, 7, 12)
        ..participants = 3
        ..route = HikingRoute(
          points: [
            RoutePoint(60, 8, elevation: 1000),
            RoutePoint(60.1, 8.1, elevation: 1200),
          ],
          source: RouteSource.trail,
          distanceMeters: 14000,
          totalAscent: 200,
          waypoints: [
            Waypoint(
              id: 'w1',
              name: 'A',
              lat: 60,
              lon: 8,
              type: WaypointType.start,
            ),
            Waypoint(
              id: 'w2',
              name: 'B',
              lat: 60.1,
              lon: 8.1,
              type: WaypointType.end,
              straightLeg: true,
            ),
          ],
        );
      final decoded = Trip.decode(t.encode());
      expect(decoded.route!.waypoints[1].straightLeg, isTrue);
      expect(decoded.name, 'Testtur');
      expect(decoded.hikingDays, 3);
      expect(decoded.route!.source, RouteSource.trail);
      expect(decoded.route!.points.length, 2);
      expect(decoded.route!.points[1].elevation, 1200);
      expect(decoded.participants, 3);
    });

    test('shareCode survives a round-trip', () {
      final t = Trip(id: 'abc', name: 'Delt')..shareCode = 'X7K2PM';
      expect(Trip.decode(t.encode()).shareCode, 'X7K2PM');
    });

    test('straightRanges out of bounds are dropped on load', () {
      final route = HikingRoute(
        points: [RoutePoint(60, 8), RoutePoint(60.01, 8), RoutePoint(60.02, 8)],
        source: RouteSource.mixed,
        straightRanges: [
          (start: 0, end: 1),
          (start: 1, end: 99),
          (start: 5, end: 2),
        ],
      );
      final decoded = HikingRoute.decode(route.encode());
      expect(decoded.straightRanges.length, 1);
      expect(decoded.straightRanges.first, (start: 0, end: 1));
    });
  });
}
