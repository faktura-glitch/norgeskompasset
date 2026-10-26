import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:norgeskompasset/core/geo.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/services/elevation_service.dart';

/// A 400-point "router" polyline climbing a steady 0.5 m per point
/// (≈200 m total). The router's own elevations sit 20 m above what the
/// elevation API answers — the real-world mismatch between BRouter's
/// SRTM and OpenTopoData/Kartverket.
List<RoutePoint> routerPoints() => List.generate(
  400,
  (i) => RoutePoint(62.5 + i * 0.0001, 7.7, elevation: 120.0 + i * 0.5),
);

double apiElevation(double lat) =>
    100.0 + ((lat - 62.5) / 0.0001).round() * 0.5;

http.Client apiClient() => MockClient((req) async {
  if (!req.url.host.contains('opentopodata')) {
    return http.Response('', 500);
  }
  final locs = req.url.queryParameters['locations']!.split('|');
  final results = [
    for (final l in locs)
      {'elevation': apiElevation(double.parse(l.split(',')[0]))},
  ];
  return http.Response(jsonEncode({'results': results}), 200);
});

void main() {
  group('ElevationService', () {
    test('route carries elevations from one source only', () async {
      final points = routerPoints();
      // Sanity: mixing router values with the API sample would blow the
      // ascent up to thousands of metres on this 200 m climb.
      final mixed = routerPoints();
      for (var i = 0; i < mixed.length; i += 2) {
        mixed[i].elevation = apiElevation(mixed[i].lat);
      }
      expect(elevationStats(mixed).ascent, greaterThan(2000));

      final filled = await ElevationService(client: apiClient())
          .fetchElevations(points);

      expect(filled, inInclusiveRange(200, 201));
      final withEle = points.where((p) => p.elevation != null).toList();
      expect(withEle.length, filled);
      // Nothing left over from the router on unsampled points.
      expect(withEle.every((p) => p.elevation == apiElevation(p.lat)), isTrue);

      final stats = elevationStats(points);
      expect(stats.ascent, inInclusiveRange(150, 210));
      expect(stats.descent, lessThan(5));
    });

    test('previous elevations are kept when every source fails', () async {
      final points = routerPoints();
      final before = [for (final p in points) p.elevation];
      final service = ElevationService(
        client: MockClient((_) async => http.Response('', 503)),
      );
      await expectLater(service.fetchElevations(points), throwsA(anything));
      expect([for (final p in points) p.elevation], before);
    });
  });
}
