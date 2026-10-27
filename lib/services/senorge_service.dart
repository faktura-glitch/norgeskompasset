import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/http_identity.dart';
import '../models/snow.dart';
import 'weather_service.dart' show ServiceException;

/// WGS84 → UTM zone 33N (EPSG:25833), the grid seNorge is served in.
/// Standard series expansion; accurate to well under a metre, which
/// is far finer than the 1 km grid it addresses.
(double east, double north) latLonToUtm33(double lat, double lon) {
  const a = 6378137.0, f = 1 / 298.257223563, k0 = 0.9996, lon0 = 15.0;
  final e2 = f * (2 - f);
  final ep2 = e2 / (1 - e2);
  final phi = lat * pi / 180;
  final dl = (lon - lon0) * pi / 180;
  final sinP = sin(phi), cosP = cos(phi), tanP = tan(phi);
  final n = a / sqrt(1 - e2 * sinP * sinP);
  final t = tanP * tanP;
  final c = ep2 * cosP * cosP;
  final aa = cosP * dl;
  final e4 = e2 * e2, e6 = e4 * e2;
  final m =
      a *
      ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi -
          (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * phi) +
          (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * phi) -
          (35 * e6 / 3072) * sin(6 * phi));
  final east =
      k0 *
          n *
          (aa +
              (1 - t + c) * pow(aa, 3) / 6 +
              (5 - 18 * t + t * t + 72 * c - 58 * ep2) * pow(aa, 5) / 120) +
      500000;
  final north =
      k0 *
      (m +
          n *
              tanP *
              (aa * aa / 2 +
                  (5 - t + 9 * c + 4 * c * c) * pow(aa, 4) / 24 +
                  (61 - 58 * t + t * t + 600 * c - 330 * ep2) *
                      pow(aa, 6) /
                      720));
  return (east, north);
}

/// Snow depth and new snow from NVE's GridTimeSeries API (seNorge).
/// Open data (NLOD), no key. Daily values, UTM33 coordinates.
class SenorgeService {
  static const _base = 'https://gts.nve.no/api/GridTimeSeries';

  /// Parses one GridTimeSeries response into daily values; entries
  /// equal to the service's NoDataValue become null.
  @visibleForTesting
  static List<double?> parseSeries(String body) {
    final j = jsonDecode(body);
    if (j is! Map) throw ServiceException('Uventet svar fra seNorge');
    if (j['Error'] != null) throw ServiceException('seNorge: ${j['Error']}');
    final noData = (j['NoDataValue'] as num?)?.toDouble() ?? 65535;
    final data = j['Data'];
    if (data is! List) throw ServiceException('seNorge: mangler data');
    return [
      for (final v in data)
        v is num && v.toDouble() != noData && v < 60000 ? v.toDouble() : null,
    ];
  }

  Future<List<double?>> _series(
    double x,
    double y,
    DateTime from,
    DateTime to,
    String theme,
  ) async {
    String d(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final url =
        '$_base/${x.round()}/${y.round()}/${d(from)}/${d(to)}/$theme.json';
    http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(url),
            headers: const {
              'Accept': 'application/json',
              if (!kIsWeb) 'User-Agent': kUserAgent,
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ServiceException('Fikk ikke kontakt med seNorge ($e)');
    }
    if (res.statusCode != 200) {
      throw ServiceException('seNorge svarte med feil (${res.statusCode})');
    }
    return parseSeries(res.body);
  }

  /// Snow at ([lat],[lon]) for [day] — or today, when [day] is in the
  /// future, since seNorge describes observed/modelled conditions and
  /// does not forecast snow depth.
  Future<SnowSample> fetchSnow(
    double lat,
    double lon,
    DateTime day, {
    int? stageNumber,
    String name = '',
  }) async {
    final (x, y) = latLonToUtm33(lat, lon);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var end = DateTime(day.year, day.month, day.day);
    if (end.isAfter(today)) end = today;
    final from = end.subtract(const Duration(days: 3));
    final depth = await _series(x, y, from, end, 'sd');
    final fresh = await _series(x, y, from, end, 'sdfsw');
    final lastDepth = depth.lastWhere((v) => v != null, orElse: () => null);
    final freshKnown = fresh.whereType<double>().toList();
    return SnowSample(
      stageNumber: stageNumber,
      name: name,
      lat: lat,
      lon: lon,
      depthCm: lastDepth,
      freshCm3d: freshKnown.isEmpty
          ? null
          : freshKnown.fold<double>(0.0, (s, v) => s + v),
      date: end,
      retrievedAt: now,
    );
  }
}
