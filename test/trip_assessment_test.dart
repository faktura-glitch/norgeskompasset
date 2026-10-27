import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/trip_assessment.dart';

/// A straight route of [km] km with a steady climb of [ascent] m.
HikingRoute _route(double km, double ascent) {
  final n = 50;
  final points = [
    for (var i = 0; i < n; i++)
      RoutePoint(
        61.0 + (km / 111.0) * i / (n - 1),
        8.5,
        elevation: 800 + ascent * i / (n - 1),
      ),
  ];
  return HikingRoute(points: points)
    ..distanceMeters = km * 1000
    ..totalAscent = ascent;
}

void main() {
  test('uten rute finnes ingen vurdering', () {
    expect(TripAssessment.forTrip(Trip(id: 't')), isNull);
  });

  test('kort og flat dagstur er en grei tur', () {
    final trip = Trip(id: 't')
      ..route = _route(6, 150)
      ..startDate = DateTime(2027, 7, 10)
      ..endDate = DateTime(2027, 7, 10);
    final a = TripAssessment.forTrip(trip)!;
    expect(a.level, AssessmentLevel.easy);
    expect(a.caveats.join(), contains('Værvarsel er ikke hentet'));
  });

  test('lang tur med stor stigning krever planlegging', () {
    final trip = Trip(id: 't')
      ..route = _route(24, 1300)
      ..startDate = DateTime(2027, 7, 10)
      ..endDate = DateTime(2027, 7, 10);
    final a = TripAssessment.forTrip(trip)!;
    expect(a.level, isNot(AssessmentLevel.easy));
    expect(a.points.join('\n'), contains('Lang distanse'));
    expect(a.points.join('\n'), contains('Stor stigning'));
  });

  test('skredterreng og barn teller med', () {
    final trip = Trip(id: 't')
      ..route = _route(14, 600)
      ..avalancheTerrain = true
      ..children = 1
      ..startDate = DateTime(2027, 3, 10)
      ..endDate = DateTime(2027, 3, 10);
    final a = TripAssessment.forTrip(trip)!;
    expect(a.level, AssessmentLevel.demanding);
    expect(a.points.join('\n'), contains('skredterreng'));
    expect(a.points.join('\n'), contains('Med barn'));
  });

  test('samme distanse over flere dager vurderes lettere', () {
    Trip trip(int days) => Trip(id: 't', accommodation: AccommodationType.cabin)
      ..route = _route(40, 1800)
      ..startDate = DateTime(2027, 7, 10)
      ..endDate = DateTime(2027, 7, 10 + days - 1);
    final one = TripAssessment.forTrip(trip(1))!;
    final three = TripAssessment.forTrip(trip(3))!;
    expect(one.level, AssessmentLevel.demanding);
    expect(three.level.index, lessThan(one.level.index));
  });
}
