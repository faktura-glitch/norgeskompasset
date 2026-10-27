import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/snow.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/packing_engine.dart';
import 'package:norgeskompasset/services/senorge_service.dart';

void main() {
  test('UTM33: sentralmeridianen gir øst 500 000', () {
    final (e, n) = latLonToUtm33(60, 15);
    expect(e, closeTo(500000, 0.5));
    expect(n, closeTo(6651411, 60));
  });

  test('UTM33: Hønefoss havner i riktig rute', () {
    final (e, n) = latLonToUtm33(60.17, 10.26);
    expect(e, closeTo(236000, 6000));
    expect(n, closeTo(6676000, 6000));
  });

  test('seNorge-svar: NoDataValue blir null', () {
    const body =
        '{"Theme":"sd","FullName":"Snødybde","NoDataValue":65535,"X":236000,'
        '"Y":6676000,"Unit":"cm","TimeResolution":1440,"Altitude":71,'
        '"Data":[0,12.5,65535,40]}';
    expect(SenorgeService.parseSeries(body), [0, 12.5, null, 40]);
    expect(
      () => SenorgeService.parseSeries(
        '{"Error":"Tema: sd. No cell exists for coordinates 0, 0."}',
      ),
      throwsA(anything),
    );
  });

  test('snø på bakken teller som vinter i pakkereglene', () {
    final start = DateTime(2027, 10, 10);
    final trip = Trip(id: 't', accommodation: AccommodationType.tent)
      ..season = TripSeason.autumn
      ..startDate = start
      ..endDate = start.add(const Duration(days: 1));
    SnowSample sample(double depth) => SnowSample(
      lat: 61.5,
      lon: 8.5,
      depthCm: depth,
      freshCm3d: 12,
      date: start,
      retrievedAt: start,
    );
    trip.snow = [sample(0)];
    expect(trip.snowSummary, 'barmark');
    expect(PackingEngine().conditionsFor(trip, null).snow, isFalse);

    trip.snow = [sample(45), sample(10)];
    expect(trip.snowSummary, 'inntil 45 cm nå, 12 cm nysnø siste 3 døgn');
    final cond = PackingEngine().conditionsFor(trip, null);
    expect(cond.snow, isTrue);
    expect(cond.snowDepthCm, 45);
    expect(Trip.decode(trip.encode()).maxSnowDepthCm, 45);
  });
}
