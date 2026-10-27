import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/what_if.dart';

/// Realistic reference trips. Each list must contain the basics, must
/// not contain gear that belongs to another kind of trip, and — once
/// everything is packed — must cover every «Hva hvis?» situation.
Trip _trip(
  String id, {
  TripActivity activity = TripActivity.foot,
  AccommodationType acc = AccommodationType.dayHike,
  TripSeason season = TripSeason.summer,
  CarryMode carry = CarryMode.backpack,
  CabinType cabin = CabinType.selfService,
  int days = 1,
  int people = 1,
  int children = 0,
  bool dog = false,
}) {
  final start = switch (season) {
    TripSeason.winter => DateTime(2027, 2, 10),
    TripSeason.spring => DateTime(2027, 4, 20),
    TripSeason.summer => DateTime(2027, 7, 10),
    TripSeason.autumn => DateTime(2027, 9, 25),
  };
  return Trip(id: id, accommodation: acc)
    ..activity = activity
    ..season = season
    ..carry = carry
    ..cabinType = cabin
    ..participants = people
    ..children = children
    ..withDog = dog
    ..startDate = start
    ..endDate = start.add(Duration(days: days - 1));
}

final _referenceTrips = <String, (Trip, Set<String>)>{
  'Sommer dagstur til fots': (
    _trip('day'),
    {'tent', 'bag-summer', 'ski', 'wax', 'pulk', 'pfd', 'helmet', 'beacon'},
  ),
  'Høst, tre netter i telt': (
    _trip(
      'autumn',
      acc: AccommodationType.tent,
      season: TripSeason.autumn,
      days: 3,
    ),
    {'ski', 'wax', 'pulk', 'pfd', 'paddle', 'hutsheet', 'helmet'},
  ),
  'Vinter, ski hytte til hytte (ubetjent)': (
    _trip(
      'ski',
      activity: TripActivity.ski,
      acc: AccommodationType.cabin,
      season: TripSeason.winter,
      cabin: CabinType.unstaffed,
      days: 4,
    ),
    {'tent', 'pfd', 'paddle', 'helmet', 'bikepump', 'mosquito'},
  ),
  'Vinter, pulk og telt': (
    _trip(
      'pulk',
      activity: TripActivity.ski,
      acc: AccommodationType.tent,
      season: TripSeason.winter,
      carry: CarryMode.pulk,
      days: 5,
      people: 2,
    ),
    {'pfd', 'paddle', 'helmet', 'bikepump', 'hutsheet', 'bag-summer'},
  ),
  'Kanotur med leir': (
    _trip(
      'canoe',
      activity: TripActivity.paddle,
      acc: AccommodationType.tent,
      carry: CarryMode.canoe,
      days: 3,
      people: 2,
    ),
    {'ski', 'wax', 'pulk', 'helmet', 'beacon', 'boots'},
  ),
  'Sykkeltur en dag': (
    _trip('bike', activity: TripActivity.bike, carry: CarryMode.bikeBags),
    {'ski', 'wax', 'pulk', 'pfd', 'tent', 'bag-summer'},
  ),
  'Løpetur': (
    _trip('run', activity: TripActivity.run),
    {'ski', 'pulk', 'pfd', 'tent', 'helmet', 'stove-summer'},
  ),
  'Familie med barn og hund på betjent hytte': (
    _trip(
      'family',
      acc: AccommodationType.cabin,
      cabin: CabinType.staffed,
      days: 2,
      people: 4,
      children: 2,
      dog: true,
    ),
    {'tent', 'stove-summer', 'ski', 'pfd', 'hutpayment'},
  ),
};

void main() {
  group('Referanseturer', () {
    for (final MapEntry(key: name, value: (trip, forbidden))
        in _referenceTrips.entries) {
      test(name, () {
        final items = PackingEngine().generate(trip);
        final ids = {for (final i in items) i.id};
        trip.packingList = items;

        expect(ids, containsAll(['firstaid', 'compass', 'windbag', 'phone']));
        expect(
          ids.contains('map') || ids.contains('mapcase'),
          isTrue,
          reason: 'papirkart mangler',
        );
        expect(
          ids.intersection(forbidden),
          isEmpty,
          reason: 'utstyr som ikke hører til turen',
        );
        expect(
          [
            for (final i in items)
              if (i.priority == PackingPriority.optional &&
                  (i.reason ?? '').isEmpty)
                i.name,
          ],
          isEmpty,
          reason: 'valgfrie forslag skal ha en begrunnelse',
        );

        for (final i in items) {
          i.packed = true;
        }
        final ctx = PackingEngine().conditionsFor(trip, null);
        for (final w in whatIfChecks(trip, ctx)) {
          expect(
            w.missing.map((c) => c.need.label),
            isEmpty,
            reason: '«${w.title}» er ikke dekket',
          );
        }
      });
    }
  });

  group('Hva hvis?', () {
    test('tom liste mangler alt, pakket utstyr dekker', () {
      final trip = _trip('empty');
      final ctx = PackingEngine().conditionsFor(trip, null);
      expect(
        whatIfChecks(trip, ctx).every((w) => w.state == NeedState.missing),
        isTrue,
      );

      trip.packingList = PackingEngine().generate(trip);
      final listed = whatIfChecks(trip, ctx);
      expect(listed.any((w) => w.state == NeedState.listed), isTrue);
      expect(listed.any((w) => w.state == NeedState.packed), isFalse);
    });

    test('padling får eget scenario', () {
      final foot = _trip('f');
      final canoe = _trip(
        'c',
        activity: TripActivity.paddle,
        carry: CarryMode.canoe,
      );
      final e = PackingEngine();
      expect(
        whatIfChecks(foot, e.conditionsFor(foot, null)).map((w) => w.title),
        isNot(contains('Dere velter i vannet')),
      );
      expect(
        whatIfChecks(canoe, e.conditionsFor(canoe, null)).map((w) => w.title),
        contains('Dere velter i vannet'),
      );
    });

    test('eget utstyr matches på navn, katalogutstyr på id', () {
      PackingItem own(String name) => PackingItem(
        id: 'u-$name',
        name: name,
        category: PackingCategory.additional,
        userAdded: true,
      );
      expect(coversNeed(own('Min hodelykt'), TripNeed.light), isTrue);
      expect(coversNeed(own('Garmin inReach'), TripNeed.call), isTrue);
      expect(coversNeed(own('Kamera'), TripNeed.light), isFalse);
      final pegs = PackingItem(
        id: 'stormstakes',
        name: 'Teltpløkker/stormbarduner ekstra',
        category: PackingCategory.additional,
      );
      expect(coversNeed(pegs, TripNeed.shelter), isFalse);
    });
  });
}
