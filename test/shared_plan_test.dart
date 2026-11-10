import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/trip.dart';

void main() {
  test('a shared plan carries the route and dates, not the packing list', () {
    final owner = Trip(
      id: 'owner',
      name: 'Besseggen',
      season: TripSeason.summer,
      participants: 4,
      shareCode: 'ABC234',
    )..packingList = [
      PackingItem(id: 'sovepose', name: 'Sovepose', category: PackingCategory.shelterSleeping),
    ];

    final json = owner.toSharedPlanJson();
    expect(json.containsKey('packingList'), isFalse);
    expect(json.containsKey('mealPlan'), isFalse);
    expect(json.containsKey('weather'), isFalse);
    expect(json.containsKey('trackLog'), isFalse);
    expect(json['shareCode'], 'ABC234');

    final mine = Trip(id: 'mine', name: 'Gammel', shareCode: 'ABC234', participants: 1)
      ..packingList = [
        PackingItem(
          id: 'min-pose',
          name: 'Min pose',
          category: PackingCategory.shelterSleeping,
          packed: true,
        ),
      ];
    mine.applySharedPlan(Trip.fromJson(json));

    expect(mine.name, 'Besseggen');
    expect(mine.season, TripSeason.summer);
    expect(mine.packingList.single.name, 'Min pose');
    expect(mine.packingList.single.packed, isTrue);
    expect(mine.participants, 1);
  });

  test('catalog id survives a save and is not copied onto a duplicate plan json by accident', () {
    final trip = Trip(id: 't', name: 'Runde')..catalogId = 'cat-1';
    expect(Trip.decode(trip.encode()).catalogId, 'cat-1');
    expect(Trip.fromSyncJson(trip.toSyncJson()).catalogId, 'cat-1');
  });
}
