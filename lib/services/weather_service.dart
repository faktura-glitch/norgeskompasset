import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../core/http_identity.dart';
import '../models/alert.dart';
import '../models/weather.dart';

class ServiceException implements Exception {
  final String message;
  const ServiceException(this.message);
  @override
  String toString() => message;
}

/// Turns a low-level network error into a short, useful reason string
/// so failures can actually be diagnosed.
String describeNetworkError(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('socketexception') || s.contains('failed host lookup')) {
    return 'ingen DNS/tilkobling';
  }
  if (s.contains('timeout')) return 'tidsavbrudd';
  if (s.contains('handshake') || s.contains('certificate')) {
    return 'TLS/brannmur blokkerte kallet';
  }
  if (s.contains('clientexception') || s.contains('xmlhttprequest')) {
    return 'nettforespørsel blokkert (CORS/nettleser)';
  }
  return e.runtimeType.toString();
}

/// MET Norway Locationforecast 2.0 (compact).
/// Free for reasonable use; requires identification via User-Agent on
/// native platforms. No API key needed.
class WeatherService {
  static const _endpoint =
      'https://api.met.no/weatherapi/locationforecast/2.0/compact';

  Future<http.Response> _getWithRetry(Uri uri) async {
    try {
      return await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      // One retry for transient failures (brief loss of connectivity).
      await Future.delayed(const Duration(seconds: 2));
      return http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    }
  }

  Map<String, String> get _headers => {
    if (!kIsWeb) 'User-Agent': kUserAgent,
    'Accept': 'application/json',
  };

  Future<WeatherSnapshot> fetchForecast(
    double lat,
    double lon, {
    double? elevation,
  }) async {
    final uri = Uri.parse(
      '$_endpoint?lat=${lat.toStringAsFixed(4)}&lon=${lon.toStringAsFixed(4)}'
      '${elevation != null ? '&altitude=${elevation.round()}' : ''}',
    );
    http.Response res;
    try {
      res = await _getWithRetry(uri);
    } catch (e) {
      throw ServiceException(
        'Fikk ikke kontakt med MET Norway (${describeNetworkError(e)}). Sjekk nettforbindelsen.',
      );
    }
    if (res.statusCode == 403) {
      throw const ServiceException(
        'MET Norway avviste forespørselen (mangler identifisering).',
      );
    }
    if (res.statusCode != 200) {
      throw ServiceException('Værdata utilgjengelig (HTTP ${res.statusCode}).');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ServiceException('Ugyldig svar fra værtjenesten.');
    }

    final props = body['properties'] as Map<String, dynamic>?;
    final timeseries = props?['timeseries'] as List? ?? [];
    final hours = <WeatherHour>[];
    for (final entry in timeseries) {
      final e = Map<String, dynamic>.from(entry as Map);
      final data = e['data'] as Map<String, dynamic>?;
      final instant = data?['instant']?['details'] as Map<String, dynamic>?;
      final next1 = data?['next_1_hours'] as Map<String, dynamic>?;
      final next6 = data?['next_6_hours'] as Map<String, dynamic>?;
      final nearest = next1 ?? next6;
      final spanHours = next1 != null ? 1.0 : 6.0;
      final details = nearest?['details'] as Map<String, dynamic>?;
      final symbol = nearest?['summary']?['symbol_code'] as String?;
      var precip = (details?['precipitation_amount'] as num?)?.toDouble();
      // Normalize 6-hour sums to per-hour amounts for display.
      if (precip != null && next1 == null) precip = precip / spanHours;
      hours.add(
        WeatherHour(
          time: DateTime.parse(e['time'] as String).toLocal(),
          temperature: (instant?['air_temperature'] as num?)?.toDouble(),
          precipitationMm: precip,
          windSpeed: (instant?['wind_speed'] as num?)?.toDouble(),
          windGust: (instant?['wind_speed_of_gust'] as num?)?.toDouble(),
          cloudCover: (instant?['cloud_area_fraction'] as num?)?.toDouble(),
          symbolCode: symbol,
        ),
      );
    }

    return WeatherSnapshot(
      lat: lat,
      lon: lon,
      elevation: elevation,
      retrievedAt: DateTime.now(),
      forecastIssuedAt: DateTime.tryParse(props?['meta']?['updated_at'] ?? ''),
      hours: hours,
    );
  }

  /// Fetches currently active official warnings (CAP/GeoJSON) for a
  /// coordinate from MET's metalerts service. Returns an empty list
  /// when nothing is in effect — absence does not mean safe.
  Future<List<MetAlert>> fetchAlerts(double lat, double lon) async {
    final uri = Uri.parse(
      'https://api.met.no/weatherapi/metalerts/2.0/current.json'
      '?lat=${lat.toStringAsFixed(4)}&lon=${lon.toStringAsFixed(4)}&lang=no',
    );
    http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ServiceException(
        'Fikk ikke kontakt med varseltjenesten (${describeNetworkError(e)}).',
      );
    }
    if (res.statusCode != 200) return [];

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final features = body['features'] as List? ?? [];
    final out = <MetAlert>[];
    for (final f in features) {
      final p = Map<String, dynamic>.from(
        (f as Map)['properties'] as Map? ?? {},
      );
      // awareness_level format: "2; yellow; Moderate"
      var level = 1;
      var levelName = '';
      final al = p['awareness_level'] as String?;
      if (al != null) {
        final parts = al.split(';');
        level = int.tryParse(parts[0].trim()) ?? 1;
        if (parts.length > 2) levelName = parts[2].trim();
      }
      // Validity window — MET uses 'when' with an ISO interval array,
      // fall back to 'timeInterval'/'timespan' shapes seen in CAP feeds.
      DateTime? from, to;
      for (final key in ['when', 'timeInterval', 'timespan']) {
        final w = p[key];
        final interval = w is Map ? w['interval'] as List? : w as List?;
        if (interval != null && interval.isNotEmpty) {
          from ??= DateTime.tryParse(interval.first.toString());
          to ??= DateTime.tryParse(interval.last.toString());
        }
      }
      out.add(
        MetAlert(
          id: (p['id'] ?? p['identifier'] ?? '').toString(),
          title: (p['title'] ?? '').toString(),
          description: (p['description'] ?? '').toString(),
          instruction: (p['instruction'] ?? '').toString(),
          event: (p['event'] ?? p['eventAwarenessName'] ?? '').toString(),
          severity: (p['severity'] ?? '').toString(),
          awarenessLevel: level,
          awarenessName: levelName,
          area:
              (p['area'] is List ? (p['area'] as List).join(', ') : p['area'])
                  ?.toString() ??
              '',
          validFrom: from,
          validTo: to,
          retrievedAt: DateTime.now(),
          lat: lat,
          lon: lon,
        ),
      );
    }
    return out;
  }
}
