import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/trip.dart';
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
}
