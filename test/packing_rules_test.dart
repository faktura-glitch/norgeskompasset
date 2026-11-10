import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/avalanche.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/snow.dart';
import 'package:norgeskompasset/models/stage.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:norgeskompasset/services/packing_engine.dart';

List<PackingItem> _gen(Trip t) => PackingEngine().generate(t);
List<String> _ids(Trip t) => _gen(t).map((i) => i.id).toList();

Trip _tent(TripSeason s, {int people = 1}) => Trip(
  id: 't',
  accommodation: AccommodationType.tent,
  season: s,
  participants: people,
  startDate: DateTime(2026, 9, 1),
  endDate: DateTime(2026, 9, 3),
);

void main() {
  test('autumn tent trip without forecast gets a tent and shoulder bag', () {
    final ids = _ids(_tent(TripSeason.autumn));
    expect(ids, containsAll(['tent', 'bag-shoulder', 'pad-summer']));
    expect(ids, isNot(contains('wintertent')));
    expect(ids, isNot(contains('bag-winter')));
  });

  test('winter tent trip gets winter shelter, not the 3-season tent', () {
    final ids = _ids(_tent(TripSeason.winter));
    expect(ids, containsAll(['wintertent', 'bag-winter', 'stove-winter']));
    expect(ids, isNot(contains('tent')));
    expect(ids, isNot(contains('bag-shoulder')));
  });

  test('summer day hike leaves the overnight kit at home', () {
    final trip = Trip(
      id: 'd',
      accommodation: AccommodationType.dayHike,
      season: TripSeason.summer,
      activity: TripActivity.foot,
      carry: CarryMode.backpack,
      startDate: DateTime(2026, 7, 10),
      endDate: DateTime(2026, 7, 10),
    );
    final ids = _ids(trip);
    for (final id in [
      'puffy',
      'beanie',
      'gloves',
      'drychange',
      'knife',
      'hygiene',
      'powerbank',
      'wool-bottom',
      'cup',
    ]) {
      expect(ids, isNot(contains(id)), reason: id);
    }
    expect(ids, containsAll(['shell', 'midlayer', 'windbag', 'pack-day', 'bottle']));
    expect(ids, contains('mosquito'));
    expect(ids, isNot(contains('cup')));
    expect(ids, isNot(contains('pack-big')));
    expect(ids, contains('rainpants'));
    expect(_gen(trip).firstWhere((i) => i.id == 'wool-socks').quantity, 1);

    trip.season = TripSeason.winter;
    final winter = _ids(trip);
    expect(winter, containsAll(['puffy', 'beanie', 'gloves', 'powerbank']));
  });

  test('one tent per two people', () {
    final tent = _gen(_tent(TripSeason.summer, people: 4))
        .firstWhere((i) => i.id == 'tent');
    expect(tent.quantity, 2);
  });

  test('multi-day bike trip uses bike bags instead of a big pack', () {
    final trip = _tent(TripSeason.summer)..activity = TripActivity.bike;
    final ids = _ids(trip);
    expect(ids, contains('bikebags'));
    expect(ids, isNot(contains('pack-big')));
  });

  test('avalanche trio is required only when terrain is confirmed', () {
    final trip = Trip(
      id: 's',
      activity: TripActivity.ski,
      season: TripSeason.winter,
    );
    PackingPriority beacon() =>
        _gen(trip).firstWhere((i) => i.id == 'beacon').priority;
    expect(beacon(), PackingPriority.recommended);
    trip.avalancheTerrain = true;
    expect(beacon(), PackingPriority.required);
    trip.avalancheTerrain = false;
    expect(_ids(trip), isNot(contains('beacon')));
  });

  test('«Ikke vurdert» fra Varsom gir ikke skredutstyr på høsttur', () {
    final trip = _tent(TripSeason.autumn, people: 3)..children = 2;
    AvalancheWarning w(int level) => AvalancheWarning(
      regId: 'r$level',
      regionName: 'Hønefoss',
      dangerLevel: level,
      lat: 60.17,
      lon: 10.26,
    );
    trip.avalancheWarnings = [w(0)];
    expect(_ids(trip), isNot(contains('beacon')));
    expect(_ids(trip), isNot(contains('shovel')));
    trip.avalancheWarnings = [w(0), w(2)];
    expect(_ids(trip), contains('beacon'));
  });

  test('mixed tent + cabin trip gets both kits', () {
    final trip = _tent(TripSeason.summer)
      ..accommodation = AccommodationType.mixed;
    expect(_ids(trip), containsAll(['tent', 'hutsheet', 'hutkey']));
  });

  test('kayak gets the canoe kit plus kayak extras', () {
    final trip = _tent(TripSeason.summer)
      ..activity = TripActivity.paddle
      ..carry = CarryMode.kayak;
    final ids = _ids(trip);
    expect(ids, containsAll(['spraydeck', 'bilgepump']));
    // Items declared for canoe still apply to a kayak.
    final canoe = _ids(
      _tent(TripSeason.summer)
        ..activity = TripActivity.paddle
        ..carry = CarryMode.canoe,
    );
    final canoeOnly = canoe.where((id) => !ids.contains(id)).toList();
    expect(canoeOnly, isEmpty);
  });

  test('children add spare clothes and snacks, scaled per child', () {
    final trip = _tent(TripSeason.summer, people: 3)..children = 2;
    final items = _gen(trip);
    expect(items.firstWhere((i) => i.id == 'kidclothes').quantity, 2);
    expect(items.any((i) => i.id == 'kidsnacks'), isTrue);
    expect(_ids(_tent(TripSeason.summer)), isNot(contains('kidclothes')));
    expect(Trip.fromJson(trip.toJson()).children, 2);
  });

  test('ski style decides skins, helmet and avalanche trio', () {
    final touring = _tent(TripSeason.winter)
      ..activity = TripActivity.ski
      ..skiStyle = SkiStyle.touring
      ..avalancheTerrain = true;
    expect(_ids(touring), containsAll(['skins', 'tourhelmet', 'beacon']));
    expect(_ids(touring), isNot(contains('wax')));

    final track = _tent(TripSeason.winter)
      ..activity = TripActivity.ski
      ..skiStyle = SkiStyle.track
      ..avalancheTerrain = false;
    final trackIds = _ids(track);
    expect(trackIds, contains('wax'));
    expect(trackIds, isNot(contains('skins')));
    expect(trackIds, isNot(contains('tourhelmet')));
    expect(trackIds, isNot(contains('beacon')));
    expect(Trip.fromJson(track.toJson()).skiStyle, SkiStyle.track);
  });

  test('snowshoes and fishing are opt-in extras', () {
    final winterFoot = _tent(TripSeason.winter);
    expect(_ids(winterFoot), isNot(contains('truger')));
    winterFoot.snowshoes = true;
    expect(_ids(winterFoot), contains('truger'));

    final fishing = _tent(TripSeason.summer)..fishing = true;
    expect(_ids(fishing), containsAll(['fishingrod', 'fishinglicense']));
    expect(_ids(_tent(TripSeason.summer)), isNot(contains('fishingrod')));
    expect(Trip.fromJson(fishing.toJson()).fishing, isTrue);
  });

  test('cabin base gets the cabin kit, a daypack and no tent', () {
    final trip = _tent(TripSeason.summer)
      ..accommodation = AccommodationType.cabinBase;
    final ids = _ids(trip);
    expect(ids, containsAll(['hutsheet', 'basedaypack']));
    expect(ids, isNot(contains('tent')));
  });

  test('trip-level dog choice overrides the profile', () {
    final trip = _tent(TripSeason.summer);
    final engine = PackingEngine();
    expect(engine.conditionsFor(trip, null).withDog, isFalse);
    trip.withDog = true;
    expect(engine.conditionsFor(trip, null).withDog, isTrue);
    final restored = Trip.fromJson(trip.toJson());
    expect(restored.withDog, isTrue);
  });

  Trip _forecasted({
    required double temp,
    required double precip,
    required double wind,
    required double forecastEle,
    required double summit,
    AccommodationType accommodation = AccommodationType.tent,
    TripSeason season = TripSeason.summer,
    TripActivity activity = TripActivity.foot,
  }) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final trip = Trip(
      id: 'wx',
      accommodation: accommodation,
      season: season,
      activity: activity,
      startDate: day,
      endDate: day,
      weather: {
        's1-0': WeatherSnapshot(
          lat: 61,
          lon: 8,
          elevation: forecastEle,
          retrievedAt: now,
          hours: [
            for (var i = 0; i < 30; i++)
              WeatherHour(
                time: day.add(Duration(hours: i)),
                temperature: temp,
                precipitationMm: i == 14 ? precip : 0,
                windSpeed: wind,
              ),
          ],
        ),
      },
    )
      ..stages = [
        Stage(
          id: 's1',
          number: 1,
          date: day,
          points: [RoutePoint(61, 8, elevation: forecastEle)],
        ),
      ]
      ..route = HikingRoute(
        points: [
          RoutePoint(61, 8, elevation: forecastEle),
          RoutePoint(61.02, 8, elevation: summit),
        ],
        highestPoint: summit,
        distanceMeters: 8000,
      );
    return trip;
  }

  test('heavy rain adds a pack liner and a spare wool layer', () {
    final wet = _forecasted(
      temp: 12,
      precip: 8,
      wind: 3,
      forecastEle: 800,
      summit: 800,
    );
    final ids = _ids(wet);
    expect(ids, containsAll(['packliner', 'wool-spare', 'rainpants']));
    expect(ids, contains('stove-summer'));
    expect(ids, isNot(contains('stove-winter')));

    final dry = _tent(TripSeason.summer);
    expect(_ids(dry), isNot(contains('packliner')));
    expect(_ids(dry), isNot(contains('wool-spare')));
  });

  test('summit lapse can switch a summer camp to a winter stove', () {
    final trip = _forecasted(
      temp: 3,
      precip: 0,
      wind: 2,
      forecastEle: 500,
      summit: 1400,
    );
    final cond = PackingEngine().conditionsFor(trip, null);
    // 900 m above the forecast point ≈ 5.9 °C colder.
    expect(cond.minTempEstimated, isTrue);
    expect(cond.minTemp!, lessThan(0));
    final ids = _ids(trip);
    expect(ids, contains('stove-winter'));
    expect(ids, isNot(contains('stove-summer')));
    expect(
      _gen(trip).firstWhere((i) => i.id == 'stove-winter').reason,
      contains('estimert'),
    );
  });

  test('crampons follow winter or freezing rain, not the calendar alone', () {
    expect(_ids(_tent(TripSeason.winter)), contains('brodder'));
    expect(_ids(_tent(TripSeason.spring)), isNot(contains('brodder')));
    final icy = _forecasted(
      temp: 0,
      precip: 2,
      wind: 3,
      forecastEle: 600,
      summit: 600,
    )..season = TripSeason.spring;
    expect(_ids(icy), contains('brodder'));
  });

  test('summer snow on the ground adds gaiters', () {
    final trip = _tent(TripSeason.summer)
      ..snow = [
        SnowSample(
          lat: 61,
          lon: 8,
          depthCm: 25,
          date: DateTime(2026, 7, 1),
          retrievedAt: DateTime(2026, 7, 1),
        ),
      ];
    expect(_ids(trip), contains('gaiters'));
  });

  test('each trip type keeps only its own kit', () {
    final run = Trip(
      id: 'run',
      accommodation: AccommodationType.dayHike,
      season: TripSeason.summer,
      activity: TripActivity.run,
      startDate: DateTime(2026, 7, 10),
      endDate: DateTime(2026, 7, 10),
    );
    final runIds = _ids(run);
    expect(runIds, contains('runshoe'));
    expect(runIds, isNot(contains('boots')));
    expect(runIds, isNot(contains('wool-top')));

    final track = Trip(
      id: 'ski',
      accommodation: AccommodationType.dayHike,
      season: TripSeason.winter,
      activity: TripActivity.ski,
      skiStyle: SkiStyle.track,
      startDate: DateTime(2026, 2, 10),
      endDate: DateTime(2026, 2, 10),
    );
    final ski = _ids(track);
    expect(ski, containsAll(['ski', 'wax']));
    expect(ski, isNot(contains('skins')));
    expect(ski, isNot(contains('tourhelmet')));
    expect(_gen(track).firstWhere((i) => i.id == 'wool-socks').quantity, 2);

    final staffed = Trip(
      id: 'cabin',
      accommodation: AccommodationType.cabin,
      season: TripSeason.summer,
      cabinType: CabinType.staffed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 3),
    );
    final cabin = _ids(staffed);
    expect(cabin, contains('cup'));
    expect(cabin, isNot(contains('waterfilter')));
    expect(cabin, isNot(contains('tent')));

    final tent = _ids(_tent(TripSeason.summer));
    expect(tent, containsAll(['cup', 'waterfilter', 'wool-top']));

    final mildAutumn = _forecasted(
      temp: 15,
      precip: 0,
      wind: 3,
      forecastEle: 400,
      summit: 500,
      accommodation: AccommodationType.dayHike,
      season: TripSeason.autumn,
    );
    final autumn = _ids(mildAutumn);
    expect(autumn, isNot(contains('puffy')));
    expect(autumn, isNot(contains('rainpants')));
    expect(autumn, isNot(contains('powerbank')));
    expect(autumn, containsAll(['shell', 'pack-day', 'mosquito']));
  });

  test('carry mode and season do not drop or borrow the wrong kit', () {
    final dayBikeBags = Trip(
      id: 'bb',
      activity: TripActivity.bike,
      carry: CarryMode.bikeBags,
      accommodation: AccommodationType.dayHike,
      season: TripSeason.summer,
      startDate: DateTime(2026, 7, 10),
      endDate: DateTime(2026, 7, 10),
    );
    expect(_ids(dayBikeBags), contains('bikebags'));
    expect(_ids(dayBikeBags), isNot(contains('pack-day')));

    final winterBike = Trip(
      id: 'wb',
      activity: TripActivity.bike,
      accommodation: AccommodationType.dayHike,
      season: TripSeason.winter,
      startDate: DateTime(2026, 2, 2),
      endDate: DateTime(2026, 2, 2),
    );
    expect(_ids(winterBike), contains('helmet'));
    expect(_ids(winterBike), isNot(contains('beacon')));

    final winterPaddle = _tent(TripSeason.winter)
      ..activity = TripActivity.paddle
      ..carry = CarryMode.canoe;
    expect(_ids(winterPaddle), contains('pfd'));
    expect(_ids(winterPaddle), isNot(contains('beacon')));
    expect(_ids(_tent(TripSeason.winter)), contains('beacon'));

    final dayPulk = Trip(
      id: 'dp',
      activity: TripActivity.foot,
      carry: CarryMode.pulk,
      accommodation: AccommodationType.dayHike,
      season: TripSeason.winter,
      startDate: DateTime(2026, 2, 2),
      endDate: DateTime(2026, 2, 2),
    );
    expect(_ids(dayPulk), contains('pulk'));
    expect(_ids(dayPulk), isNot(contains('pulk-daypack')));
    expect(
      _gen(dayPulk).firstWhere((i) => i.id == 'drybags-pulk').reason,
      isNot(contains('Sovepose')),
    );
    expect(
      _ids(_tent(TripSeason.winter)..carry = CarryMode.pulk),
      contains('pulk-daypack'),
    );

    final touring = _tent(TripSeason.winter)
      ..activity = TripActivity.ski
      ..skiStyle = SkiStyle.touring;
    expect(_ids(touring), contains('crampons'));
    expect(
      _ids(
        _tent(TripSeason.winter)
          ..activity = TripActivity.ski
          ..skiStyle = SkiStyle.track,
      ),
      isNot(contains('crampons')),
    );

    expect(
      _ids(_tent(TripSeason.summer)..withDog = true),
      isNot(contains('dogsocks')),
    );
    expect(
      _ids(_tent(TripSeason.winter)..withDog = true),
      contains('dogsocks'),
    );
  });
}
