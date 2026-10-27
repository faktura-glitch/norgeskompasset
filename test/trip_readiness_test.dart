import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/trip_readiness.dart';

TripReadiness _eval(Trip trip) =>
    TripReadiness.evaluate(trip, PackingEngine().conditionsFor(trip, null));

void main() {
  test('tom tur: rute, dato og pakkeliste mangler', () {
    final r = _eval(Trip(id: 't'));
    expect(r.levelFor(ReadinessArea.route), ReadinessLevel.missing);
    expect(r.levelFor(ReadinessArea.gear), ReadinessLevel.missing);
    expect(r.ready, isFalse);
    expect(r.percent, lessThan(100));
    expect(r.headline, contains('Turklarhet'));
  });

  test('dagstur over to dager flagges', () {
    final start = DateTime(2027, 7, 10);
    final trip = Trip(id: 't', accommodation: AccommodationType.dayHike)
      ..startDate = start
      ..endDate = start.add(const Duration(days: 1));
    final texts = _eval(trip).issues.map((i) => i.text).join('\n');
    expect(texts, contains('Dagstur over 2 dager'));
  });

  test('værvarsel som ikke er hentet er en merknad, ikke et hull', () {
    final trip = Trip(id: 't')..startDate = DateTime(2027, 7, 10);
    expect(_eval(trip).levelFor(ReadinessArea.weather), ReadinessLevel.check);
  });

  test(
    'generert liste dekker førstehjelp og kart; tom liste gjør det ikke',
    () {
      final trip = Trip(id: 't')..startDate = DateTime(2027, 7, 10);
      trip.packingList = PackingEngine().generate(trip);
      final full = _eval(trip);
      expect(
        full.levelFor(ReadinessArea.safety),
        isNot(ReadinessLevel.missing),
      );

      trip.packingList = trip.packingList
          .where((i) => i.name.toLowerCase().contains('lykt'))
          .toList();
      final stripped = _eval(trip);
      final texts = stripped.issues.map((i) => i.text).join('\n');
      expect(texts, contains('Førstehjelp mangler'));
      expect(texts, contains('navigasjon'));
      expect(stripped.levelFor(ReadinessArea.safety), ReadinessLevel.missing);
      expect(stripped.percent, lessThan(full.percent));
    },
  );
}
