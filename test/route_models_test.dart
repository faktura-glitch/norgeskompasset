import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/core/geo.dart';
import 'package:norgeskompasset/models/route_models.dart';

HikingRoute oneWay() => HikingRoute(
  points: [
    RoutePoint(60.00, 8.0, elevation: 100),
    RoutePoint(60.01, 8.0, elevation: 300),
    RoutePoint(60.02, 8.0, elevation: 250),
    RoutePoint(60.03, 8.0, elevation: 500),
  ],
  distanceMeters: 3000,
  straightRanges: const [(start: 2, end: 3)],
);

void main() {
  group('Tur-retur', () {
    test('mirrors the way back and doubles the numbers', () {
      final r = oneWay()..makeOutAndBack();
      expect(r.outAndBack, isTrue);
      expect(r.turnIndex, 3);
      expect(r.points.length, 7);
      expect(r.points.last.lat, 60.00);
      expect(r.points[4].elevation, 250);
      expect(r.distanceMeters, 6000);
      expect(
        r.straightRanges,
        containsAll([(start: 2, end: 3), (start: 3, end: 4)]),
      );
      // Up 450 / down 50 one way → 500 / 500 for the whole trip.
      final s = elevationStats(r.points);
      expect(s.ascent, 500);
      expect(s.descent, 500);
      expect(s.highest, 500);
      // Idempotent.
      r.makeOutAndBack();
      expect(r.points.length, 7);
    });

    test('switching back restores the one-way route', () {
      final r = oneWay()
        ..makeOutAndBack()
        ..makeOneWay();
      expect(r.outAndBack, isFalse);
      expect(r.points.length, 4);
      expect(r.distanceMeters, 3000);
      expect(r.straightRanges, [(start: 2, end: 3)]);
    });

    test('survives both JSON formats', () {
      final r = oneWay()..makeOutAndBack();
      expect(HikingRoute.fromJson(r.toJson()).turnIndex, 3);
      expect(HikingRoute.fromCompactJson(r.toCompactJson()).turnIndex, 3);
      // A turn index that no longer fits the point list is dropped.
      final j = r.toJson()..['turnIndex'] = 42;
      expect(HikingRoute.fromJson(j).outAndBack, isFalse);
    });
  });
}
