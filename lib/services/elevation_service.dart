import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/route_models.dart';
import 'weather_service.dart' show ServiceException, describeNetworkError;

/// Elevation data with two sources:
/// - OpenTopoData (Mapzen Terrarium, ~30 m): primary, batch API.
///   NOTE: no CORS headers, so it is unavailable in browser builds.
/// - Kartverket høydedata (DTM1, 1 m, Norway only): fallback,
///   CORS-enabled but single-point — used for a sampled subset.
///
/// Returns null values for points where no data exists — callers must
/// treat elevation as optional.
///
/// A route only ever carries elevations from ONE source at a time.
/// The router (BRouter) already delivers an elevation per point; if
/// those were kept on the points we do not sample here, the profile
/// would alternate between two datasets that disagree by 10–30 m
/// and the ascent sum would explode (thousands of metres on a short
/// walk). So every point is cleared before the fetched sample is
/// written back, and the previous values are restored if the fetch
/// fails entirely.
class ElevationService {
  static const _otdEndpoint = 'https://api.opentopodata.org/v1/mapzen';
  static const _kartverketEndpoint =
      'https://ws.geonorge.no/hoydedata/v1/punkt';
  static const _batchSize = 90; // API allows 100/req; keep margin.

  final http.Client _client;

  ElevationService({http.Client? client}) : _client = client ?? http.Client();

  /// Fills in [RoutePoint.elevation] for the supplied points.
  /// Returns the number of points that received an elevation value.
  Future<int> fetchElevations(List<RoutePoint> points) async {
    if (points.isEmpty) return 0;

    final before = [for (final p in points) p.elevation];
    for (final p in points) {
      p.elevation = null;
    }
    try {
      // On web, OpenTopoData cannot be called (no CORS) — go straight
      // to the Kartverket fallback with a smaller sample.
      if (kIsWeb) return await _fetchFromKartverket(_sample(points, 25));

      // Sample at most ~200 points evenly — full polyline density is
      // unnecessary for the profile and stays within rate limits.
      try {
        return await _fetchFromOpenTopoData(_sample(points, 200));
      } catch (_) {
        // Fall back to Kartverket (Norway only, single-point calls).
        // Drop any partial OpenTopoData batch first — one source only.
        for (final p in points) {
          p.elevation = null;
        }
        return await _fetchFromKartverket(_sample(points, 25));
      }
    } catch (_) {
      for (var i = 0; i < points.length; i++) {
        points[i].elevation = before[i];
      }
      rethrow;
    }
  }

  Future<int> _fetchFromOpenTopoData(List<RoutePoint> sampled) async {
    var filled = 0;
    for (var i = 0; i < sampled.length; i += _batchSize) {
      final batch = sampled.sublist(
        i,
        (i + _batchSize).clamp(0, sampled.length),
      );
      final locations = batch
          .map((p) => '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}')
          .join('|');
      final uri = Uri.parse('$_otdEndpoint?locations=$locations');
      http.Response res;
      try {
        res = await _client.get(uri).timeout(const Duration(seconds: 20));
      } catch (e) {
        throw ServiceException(
          'Fikk ikke kontakt med høydedatatjenesten (${describeNetworkError(e)}).',
        );
      }
      if (res.statusCode != 200) {
        throw ServiceException(
          'Høydedata utilgjengelig (HTTP ${res.statusCode}).',
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];
      for (var j = 0; j < results.length && j < batch.length; j++) {
        final ele = (results[j] as Map<String, dynamic>)['elevation'];
        if (ele != null) {
          batch[j].elevation = (ele as num).toDouble();
          filled++;
        }
      }
      if (i + _batchSize < sampled.length) {
        // Respect the public API's ~1 req/s guideline.
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    if (filled == 0) {
      throw const ServiceException('Ingen høydepunkter returnert.');
    }
    return filled;
  }

  /// Kartverket høydedata 'punkt' — single coordinate per request,
  /// so we only sample key points (Norway coverage only).
  Future<int> _fetchFromKartverket(List<RoutePoint> sampled) async {
    var filled = 0;
    Object? lastError;
    for (final p in sampled) {
      try {
        final uri = Uri.parse(
          '$_kartverketEndpoint'
          '?nord=${p.lat.toStringAsFixed(5)}&ost=${p.lon.toStringAsFixed(5)}&koordsys=4326&geojson=false',
        );
        final res = await _client.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final punkter = body['punkter'] as List? ?? [];
          if (punkter.isNotEmpty) {
            final z = punkter.first['z'];
            if (z != null) {
              p.elevation = (z as num).toDouble();
              filled++;
            }
          }
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (filled == 0) {
      throw ServiceException(
        'Høydedata utilgjengelig fra begge kilder${lastError != null ? ' (${describeNetworkError(lastError)})' : ''}.',
      );
    }
    return filled;
  }

  List<RoutePoint> _sample(List<RoutePoint> points, int maxCount) {
    if (points.length <= maxCount) return points;
    final out = <RoutePoint>[];
    final step = points.length / maxCount;
    for (var i = 0; i < maxCount; i++) {
      out.add(points[(i * step).floor()]);
    }
    if (out.last != points.last) out.add(points.last);
    return out;
  }
}
