import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:norgeskompasset/core/geo.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/trip.dart';

void main() {
  group('Via-punkt plassering', () {
    // Start A → via V → goal B along a line heading east.
    final anchors = [
      const LatLng(60.0, 8.00),
      const LatLng(60.0, 8.10),
      const LatLng(60.0, 8.20),
    ];

    test('a tap between A and V is inserted before V, not before B', () {
      expect(nearestLegIndex(anchors, const LatLng(60.005, 8.05)), 1);
    });

    test('a tap between V and B goes before B', () {
      expect(nearestLegIndex(anchors, const LatLng(59.995, 8.15)), 2);
    });

    test('with fewer than two anchors the point is appended', () {
      expect(nearestLegIndex([anchors.first], anchors.last), 1);
      expect(nearestLegIndex(const [], anchors.last), 0);
    });
  });

  group('Anbefalt dagsoppdeling', () {
    test('a day hike stays one day', () {
      expect(recommendedTripDays(6 * 60), 1);
      expect(recommendedTripDays(0), 1);
    });

    test('11 h is two days for adults, with children 6 h a day', () {
      expect(recommendedTripDays(11 * 60), 2);
      expect(recommendedTripDays(11 * 60, withChildren: true), 2);
      expect(recommendedTripDays(13 * 60, withChildren: true), 3);
    });

    test('never more than 14 days', () {
      expect(recommendedTripDays(1000 * 60), 14);
    });
  });

  group('Høydedekning', () {
    // 1000 router points over ~11 km; elevation on every 5th point,
    // exactly like the sampled fetch leaves the route.
    List<RoutePoint> sampled() => List.generate(
      1000,
      (i) => RoutePoint(
        60.0 + i * 0.0001,
        8.0,
        elevation: i % 5 == 0 ? 100 : null,
      ),
    );

    test('an evenly sampled route counts as fully covered', () {
      expect(elevationCoverage(sampled()), greaterThan(0.99));
    });

    test('a route with elevation only on the first half is half covered', () {
      final pts = sampled();
      for (var i = 500; i < pts.length; i++) {
        pts[i].elevation = null;
      }
      final c = elevationCoverage(pts);
      expect(c, greaterThan(0.45));
      expect(c, lessThan(0.55));
    });

    test('a sparse route with elevation on every point is fully covered', () {
      expect(
        elevationCoverage([
          RoutePoint(60, 8, elevation: 100),
          RoutePoint(60.05, 8, elevation: 300),
        ]),
        1.0,
      );
    });

    test('no elevation at all is zero', () {
      expect(elevationCoverage([RoutePoint(60, 8), RoutePoint(60.1, 8)]), 0);
    });
  });

  group('Løping', () {
    test('is faster than walking on the same route', () {
      final walk = estimateHikingMinutes(10000, 400, 400, HikingPace.normal);
      final run = estimateHikingMinutes(
        10000,
        400,
        400,
        HikingPace.normal,
        activity: TripActivity.run,
      );
      expect(run, lessThan(walk));
      expect(TripActivity.run.onFoot, isTrue);
      expect(TripActivity.bike.onFoot, isFalse);
    });
  });
}
