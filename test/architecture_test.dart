import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/planning_context.dart';
import 'package:norgeskompasset/models/profile.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/stage.dart';
import 'package:norgeskompasset/models/track.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:norgeskompasset/services/meal_planner.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/planning_context.dart';

Trip _trip({
  AccommodationType acc = AccommodationType.tent,
  TripActivity activity = TripActivity.foot,
  CarryMode carry = CarryMode.backpack,
  TripSeason season = TripSeason.summer,
  int days = 3,
}) {
  final t = Trip(
    id: 't1',
    accommodation: acc,
    activity: activity,
    carry: carry,
    season: season,
  );
  t.startDate = DateTime(2026, 7, 1);
  t.endDate = t.startDate!.add(Duration(days: days - 1));
  return t;
}

HikingRoute _route({RouteSource source = RouteSource.trail}) {
  final pts = List.generate(
    12,
    (i) => RoutePoint(60.0 + i * 0.01, 8.0, elevation: 900 + i * 20),
  );
  return HikingRoute(
    points: pts,
    source: source,
    distanceMeters: 12000,
    totalAscent: 220,
    totalDescent: 40,
    highestPoint: 1120,
  );
}

Set<String> _ids(List<PackingItem> items) => items.map((i) => i.id).toSet();

void main() {
  group('Activity/carry exclusion matrix', () {
    test('pulk on foot excludes all ski gear, keeps traction gear', () {
      final items = PackingEngine().generate(
        _trip(carry: CarryMode.pulk, season: TripSeason.winter),
      );
      final ids = _ids(items);
      // Ski equipment is mutually exclusive with foot travel.
      for (final id in ['ski', 'skistaves', 'skiboots', 'skins', 'wax']) {
        expect(ids, isNot(contains(id)), reason: '$id must not appear');
      }
      // Winter traction gear for pulk-on-foot is forced in.
      expect(ids, containsAll(['truger', 'brodder', 'gaiters', 'pulk']));
    });

    test('canoe excludes bike/ski gear, locks in PFD and drybags', () {
      final items = PackingEngine().generate(
        _trip(activity: TripActivity.paddle, carry: CarryMode.canoe),
      );
      final ids = _ids(items);
      for (final id in [
        'bikepump',
        'bikelights',
        'bikegloves',
        'bikelock',
        'ski',
        'skins',
      ]) {
        expect(ids, isNot(contains(id)), reason: '$id must not appear');
      }
      expect(ids, containsAll(['pfd', 'drybags', 'paddle', 'sparepaddle']));
      expect(
        items.firstWhere((i) => i.id == 'pfd').priority,
        PackingPriority.required,
      );
    });

    test('bike excludes paddle and pulk gear', () {
      final items = PackingEngine().generate(
        _trip(activity: TripActivity.bike),
      );
      final ids = _ids(items);
      for (final id in ['pfd', 'paddle', 'pulk', 'ski', 'truger']) {
        expect(ids, isNot(contains(id)), reason: '$id must not appear');
      }
    });

    test('generated items carry stable catalog ids', () {
      final items = PackingEngine().generate(_trip());
      expect(items.map((i) => i.id), isNot(contains(''))); // all set
      // Same trip conditions → identical ids across generations.
      final again = PackingEngine().generate(_trip());
      expect(_ids(again), _ids(items));
    });
  });

  test('only an entirely trail-routed line supports deviation alerts', () {
    expect(_route().supportsDeviationAlerts, isTrue);
    for (final source in [
      RouteSource.estimated,
      RouteSource.manual,
      RouteSource.mixed,
    ]) {
      expect(_route(source: source).supportsDeviationAlerts, isFalse);
    }
    final trailWithStraightLeg = _route()
      ..straightRanges = [(start: 2, end: 4)];
    expect(trailWithStraightLeg.supportsDeviationAlerts, isFalse);
  });

  group('Tombstones and state preservation', () {
    test('dismissed suggestion stays gone on regeneration', () {
      final t = _trip();
      t.packingList = PackingEngine().generate(t);
      final target = t.packingList.firstWhere(
        (i) => i.id == 'headlamp',
        orElse: () => t.packingList.first,
      );
      t.packingList.removeWhere((i) => i.id == target.id);
      t.deletedGearIds.add(target.id);

      t.packingList = PackingEngine().generate(t);
      expect(
        t.packingList.any((i) => i.id == target.id),
        isFalse,
        reason: 'a removed suggestion must not silently reappear',
      );
      // Undoing the tombstone brings it back on the next regeneration.
      t.deletedGearIds.remove(target.id);
      t.packingList = PackingEngine().generate(t);
      expect(t.packingList.any((i) => i.id == target.id), isTrue);
    });

    test('packed state and user weights survive by id', () {
      final t = _trip();
      t.packingList = PackingEngine().generate(t);
      final item = t.packingList.firstWhere(
        (i) => i.id == 'compass',
        orElse: () => t.packingList.first,
      );
      item.packed = true;
      item.unitWeightGrams = 123;

      t.packingList = PackingEngine().generate(t);
      final regen = t.packingList.firstWhere((i) => i.id == item.id);
      expect(regen.packed, isTrue);
      expect(regen.unitWeightGrams, 123);
    });

    test(
      'edited name, quantity and priority survive trip changes and sync',
      () {
        final t = _trip();
        t.packingList = PackingEngine().generate(t);
        final original = t.packingList.firstWhere(
          (i) => i.id == 'compass',
          orElse: () => t.packingList.first,
        );
        original
          ..name = 'Mitt ${original.name}'
          ..quantity = 4
          ..priority = PackingPriority.required
          ..unitWeightGrams = 321
          ..nameEdited = true
          ..quantityEdited = true
          ..priorityEdited = true
          ..weightEdited = true;
        t.participants = 2;
        final restored = Trip.fromSyncJson(t.toSyncJson());
        restored.packingList = PackingEngine().generate(restored);
        final result = restored.packingList.firstWhere(
          (i) => i.id == original.id,
        );
        expect(result.name, original.name);
        expect(result.quantity, 4);
        expect(result.priority, PackingPriority.required);
        expect(result.unitWeightGrams, 321);
        expect(result.nameEdited, isTrue);
        expect(result.weightEdited, isTrue);
      },
    );

    test('legacy lists still merge by name fallback', () {
      final t = _trip();
      t.packingList = PackingEngine().generate(t);
      final legacy = t.packingList.firstWhere((i) => !i.userAdded);
      // Simulate a pre-stable-id list: random id, same name, packed.
      final fake = PackingItem(
        id: 'old-random-id',
        name: legacy.name,
        category: legacy.category,
        packed: true,
        unitWeightGrams: 77,
      );
      t.packingList = [fake];
      t.packingList = PackingEngine().generate(t);
      final merged = t.packingList.firstWhere((i) => i.id == legacy.id);
      expect(merged.packed, isTrue);
      expect(merged.unitWeightGrams, 77);
    });
  });

  group('PlanningContext bridge', () {
    final profile = UserProfile();

    test('exposes route facts and estimated legs honestly', () {
      final t = _trip()..route = _route(source: RouteSource.estimated);
      final ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.distanceKm, closeTo(12, 0.1));
      expect(ctx.routeSource, RouteSource.estimated);
      expect(ctx.hasEstimatedLegs, isTrue);
      expect(ctx.elevationCoverage, 1.0);
      expect(ctx.userChecks.any((c) => c.contains('estimert')), isTrue);
      expect(ctx.userChecks.any((c) => c.contains('værprognose')), isTrue);
    });

    test('weather freshness is classified, never fabricated', () {
      final t = _trip()..route = _route();
      final now = DateTime.now();
      t.startDate = DateTime(now.year, now.month, now.day + 1);
      t.endDate = t.startDate!.add(const Duration(days: 2));
      var ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.weatherQuality, DataQuality.missing);

      t.weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: now,
        hours: [
          for (var i = 0; i < 24 * 10; i++)
            WeatherHour(time: now.add(Duration(hours: i)), temperature: 5),
        ],
      );
      ctx = PlanningContextBuilder.forTrip(t, profile);
      // 10-day hours cover the 3-day trip → good.
      expect(ctx.weatherQuality, DataQuality.good);
      expect(ctx.userChecks.where((c) => c.contains('prognose')), isEmpty);

      t.weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: now,
        hours: [
          WeatherHour(
            time: t.endDate!.add(const Duration(hours: 2)),
            temperature: 5,
          ),
        ],
      );
      ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.weatherQuality, DataQuality.partial);

      t.weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: now.subtract(const Duration(hours: 30)),
        hours: [WeatherHour(time: now, temperature: 5)],
      );
      ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.weatherQuality, DataQuality.stale);
    });

    test('a forecast for only one stage is marked partial', () {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day + 1);
      final t = _trip()..startDate = start;
      t.endDate = start.add(const Duration(days: 1));
      t.stages = [
        Stage(id: 'first', number: 1, date: start),
        Stage(id: 'second', number: 2, date: t.endDate),
      ];
      t.weather['first'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: now,
        hours: [
          for (var i = 0; i < 24; i++)
            WeatherHour(
              time: start.add(Duration(hours: 6 + i)),
              temperature: 5,
            ),
        ],
      );
      expect(
        PlanningContextBuilder.forTrip(t, UserProfile()).weatherQuality,
        DataQuality.partial,
      );
    });

    test('avalanche basis distinguishes warning, answer and unknown', () {
      final profile = UserProfile();
      var t = _trip(season: TripSeason.winter);
      var ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.avalancheBasis, AvalancheBasis.notAssessed);
      expect(ctx.userChecks.any((c) => c.contains('Skred')), isTrue);

      t = _trip(season: TripSeason.winter)..avalancheTerrain = false;
      ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.avalancheBasis, AvalancheBasis.userExcluded);

      t = _trip(season: TripSeason.summer);
      ctx = PlanningContextBuilder.forTrip(t, profile);
      expect(ctx.avalancheBasis, AvalancheBasis.notRelevant);
    });

    test('stale weather does not set packing temperature', () {
      final now = DateTime.now();
      final t = _trip()
        ..startDate = DateTime(now.year, now.month, now.day)
        ..endDate = DateTime(now.year, now.month, now.day);
      t.stages = [Stage(id: 'day-1', number: 1, date: t.startDate)];
      t.weather['day-1'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: now.subtract(const Duration(days: 2)),
        hours: [
          WeatherHour(
            time: DateTime(now.year, now.month, now.day, 7),
            temperature: -15,
          ),
        ],
      );
      expect(PackingEngine().conditionsFor(t, profile).minTemp, isNull);
      expect(
        PlanningContextBuilder.forTrip(t, profile).weatherQuality,
        DataQuality.stale,
      );
    });
  });

  group('Energy-aware meal scaling', () {
    test('portions scale up toward a high route-based target', () {
      final t = _trip(days: 2);
      final plain = MealPlanner.generate(t);
      final scaled = MealPlanner.generate(t, targetKcalPerDay: 4500);
      for (var i = 0; i < scaled.meals.length; i++) {
        expect(
          scaled.meals[i].gramsPerPerson,
          greaterThan(plain.meals[i].gramsPerPerson),
        );
      }
      // Rounded to 10 g and capped — never absurdly large.
      for (final m in scaled.meals) {
        expect(m.gramsPerPerson % 10, 0);
      }
    });

    test('reasonable target leaves defaults untouched', () {
      final t = _trip(days: 1);
      final plain = MealPlanner.generate(t);
      // ~2000 kcal/day is roughly what the default day ration gives.
      final target = plain.totalKcalPerPerson;
      final scaled = MealPlanner.generate(t, targetKcalPerDay: target);
      expect(
        scaled.meals.map((m) => m.gramsPerPerson).toList(),
        plain.meals.map((m) => m.gramsPerPerson).toList(),
      );
    });
  });

  group('Compact sync snapshot (v2)', () {
    Trip fullTrip() {
      final t = _trip(days: 2)
        ..route = _route()
        ..name = 'Testtur';
      t.packingList = PackingEngine().generate(t);
      t.mealPlan = MealPlanner.generate(t);
      t.deletedGearIds.add('goggles');
      t.weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: DateTime.now(),
        hours: [WeatherHour(time: DateTime.now(), temperature: 8)],
      );
      t.trackLog = [TrackPoint(60.1, 8.1, 900, DateTime.now())];
      return t;
    }

    test('round-trips choices, route, packing state and tombstones', () {
      final t = fullTrip();
      final restored = Trip.fromSyncJson(t.toSyncJson());
      expect(restored.id, t.id);
      expect(restored.activity, t.activity);
      expect(restored.route!.points.length, t.route!.points.length);
      expect(restored.route!.source, t.route!.source);
      expect(restored.packingList.length, t.packingList.length);
      expect(restored.deletedGearIds, contains('goggles'));
      expect(restored.mealPlan!.days, t.mealPlan!.days);
      // Stages are rebuilt deterministically from the route.
      expect(restored.stages, isNotEmpty);
      expect(restored.stages.length, t.hikingDays);
    });

    test('omits volatile/derived data and shrinks the document', () {
      final t = fullTrip();
      final full = t.encode();
      final compact = jsonEncode(t.toSyncJson());
      final j = jsonDecode(compact) as Map<String, dynamic>;
      expect(j.containsKey('weather'), isFalse);
      expect(j.containsKey('stages'), isFalse);
      expect(j.containsKey('trackLog'), isFalse);
      expect(j.containsKey('alerts'), isFalse);
      expect(j.containsKey('avalanche'), isFalse);
      expect(compact.length, lessThan(full.length));
    });

    test('decodeAny reads both schemas', () {
      final t = fullTrip();
      final fromV2 = Trip.decodeAny(jsonEncode(t.toSyncJson()));
      expect(fromV2.name, 'Testtur');
      final fromLegacy = Trip.decodeAny(t.encode());
      expect(fromLegacy.name, 'Testtur');
      expect(fromLegacy.stages.length, t.stages.length);
    });
  });
}
