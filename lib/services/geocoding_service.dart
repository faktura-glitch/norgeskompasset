import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/http_identity.dart';
import 'weather_service.dart' show ServiceException, describeNetworkError;

class PlaceResult {
  final String name;
  final String displayName;
  final String type;
  final LatLng point;

  /// 'Kartverket' for SSR, 'OpenStreetMap' for Nominatim.
  final String source;

  const PlaceResult({
    required this.name,
    required this.displayName,
    required this.type,
    required this.point,
    this.source = '',
  });
}

/// Place search. Official names come from Kartverket's stedsnavn
/// register (SSR). Nominatim is only asked when SSR has nothing, or
/// when the query looks like a street address with a house number.
///
/// Both are free. Search-as-you-type is debounced by callers.
class GeocodingService {
  static const _nominatim = 'https://nominatim.openstreetmap.org/search';
  static const _nominatimReverse = 'https://nominatim.openstreetmap.org/reverse';
  static const _ssrNavn = 'https://ws.geonorge.no/stedsnavn/v1/navn';
  static const _ssrPunkt = 'https://ws.geonorge.no/stedsnavn/v1/punkt';

  /// Nearest place name for a tapped map point, or null when both
  /// registers fail. SSR wins inside 1 km; otherwise Nominatim.
  Future<String?> reverse(LatLng point) async {
    try {
      final name = await _reverseSsr(point);
      if (name != null) return name;
    } catch (_) {}
    return _reverseNominatim(point);
  }

  /// Picks a short, human place name from a Nominatim reverse result.
  static String? placeNameFrom(Map<String, dynamic> m) {
    final name = (m['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final address = m['address'];
    if (address is Map) {
      for (final key in const [
        'peak',
        'natural',
        'locality',
        'hamlet',
        'village',
        'suburb',
        'town',
        'city',
        'municipality',
      ]) {
        final v = (address[key] as String?)?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    List<PlaceResult> ssr = [];
    Object? ssrError;
    try {
      ssr = await _searchSsr(q);
    } catch (e) {
      ssrError = e;
    }
    final wantsAddress = RegExp(r'\d').hasMatch(q);
    if (ssr.isNotEmpty && !wantsAddress) return ssr;
    try {
      final osm = await _searchNominatim(q);
      if (ssr.isEmpty) return osm;
      return _merge(ssr, osm);
    } catch (e) {
      if (ssr.isNotEmpty) return ssr;
      if (ssrError is ServiceException) throw ssrError;
      throw ServiceException(
        'Fikk ikke kontakt med stedssøket (${describeNetworkError(e)}).',
      );
    }
  }

  Future<List<PlaceResult>> _searchSsr(String query) async {
    final uri = Uri.parse(_ssrNavn).replace(
      queryParameters: {
        'sok': query,
        'fuzzy': 'true',
        'utkoordsys': '4258',
        'treffPerSide': '8',
      },
    );
    final body = await _getJson(uri, 'Stedsnavnregisteret');
    return parseSsrSearch(body, query: query);
  }

  Future<String?> _reverseSsr(LatLng point) async {
    final uri = Uri.parse(_ssrPunkt).replace(
      queryParameters: {
        'nord': point.latitude.toStringAsFixed(5),
        'ost': point.longitude.toStringAsFixed(5),
        'koordsys': '4258',
        'radius': '1000',
        'treffPerSide': '8',
      },
    );
    final body = await _getJson(uri, 'Stedsnavnregisteret');
    return closestSsrName(body);
  }

  Future<String?> _reverseNominatim(LatLng point) async {
    final uri = Uri.parse(_nominatimReverse).replace(
      queryParameters: {
        'format': 'jsonv2',
        'lat': point.latitude.toStringAsFixed(5),
        'lon': point.longitude.toStringAsFixed(5),
        'zoom': '15',
        'accept-language': 'nb',
      },
    );
    try {
      final res = await http
          .get(uri, headers: {if (!kIsWeb) 'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map
          ? placeNameFrom(Map<String, dynamic>.from(body))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<PlaceResult>> _searchNominatim(String query) async {
    final uri = Uri.parse(_nominatim).replace(
      queryParameters: {
        'format': 'jsonv2',
        'q': query,
        'countrycodes': 'no',
        'limit': '6',
        'accept-language': 'nb',
      },
    );
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {if (!kIsWeb) 'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      throw ServiceException(
        'Fikk ikke kontakt med stedssøket (${describeNetworkError(e)}).',
      );
    }
    if (res.statusCode != 200) {
      throw ServiceException('Stedssøk feilet (HTTP ${res.statusCode}).');
    }
    final list = jsonDecode(res.body) as List? ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final name = (m['name'] as String?)?.isNotEmpty == true
          ? m['name'] as String
          : (m['display_name'] as String).split(',').first;
      return PlaceResult(
        name: name,
        displayName: m['display_name'] as String? ?? name,
        type: m['type'] as String? ?? m['category'] as String? ?? '',
        point: LatLng(
          double.parse(m['lat'] as String),
          double.parse(m['lon'] as String),
        ),
        source: 'OpenStreetMap',
      );
    }).toList();
  }

  Future<Object?> _getJson(Uri uri, String what) async {
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {if (!kIsWeb) 'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      throw ServiceException(
        'Fikk ikke kontakt med $what (${describeNetworkError(e)}).',
      );
    }
    if (res.statusCode != 200) {
      throw ServiceException('$what svarte med HTTP ${res.statusCode}.');
    }
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw ServiceException('$what kunne ikke leses.');
    }
  }

  List<PlaceResult> _merge(List<PlaceResult> ssr, List<PlaceResult> osm) {
    final out = [...ssr];
    for (final place in osm) {
      final duplicate = ssr.any((s) => _near(s.point, place.point));
      if (!duplicate) out.add(place);
      if (out.length >= 8) break;
    }
    return out;
  }

  bool _near(LatLng a, LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLon =
        (a.longitude - b.longitude) * math.cos(a.latitude * math.pi / 180);
    return dLat * dLat + dLon * dLon < 0.004 * 0.004;
  }
}

/// One SSR hit before it becomes a [PlaceResult]. Public so tests can
/// check ranking without the network.
class SsrHit {
  final String name;
  final String type;
  final String kommune;
  final String fylke;
  final LatLng point;
  final bool historical;
  final int? meters;

  const SsrHit({
    required this.name,
    required this.type,
    required this.point,
    this.kommune = '',
    this.fylke = '',
    this.historical = false,
    this.meters,
  });

  PlaceResult toPlace() {
    final where = [
      type,
      [kommune, fylke].where((s) => s.isNotEmpty).join(', '),
      'Kartverket',
    ].where((s) => s.isNotEmpty).join(' · ');
    return PlaceResult(
      name: name,
      displayName: where,
      type: type,
      point: point,
      source: 'Kartverket',
    );
  }
}

/// Parses a `/navn` search document. Active names stay in the order
/// Kartverket returned; historical and relic names sink to the end.
List<PlaceResult> parseSsrSearch(Object? body, {String query = ''}) {
  final hits = _readSsr(body, searchShape: true);
  final needle = query.trim().toLowerCase();
  final indexed = hits.indexed.toList();
  indexed.sort((a, b) {
    final ae = needle.isNotEmpty && a.$2.name.toLowerCase() == needle;
    final be = needle.isNotEmpty && b.$2.name.toLowerCase() == needle;
    if (ae != be) return ae ? -1 : 1;
    if (a.$2.historical != b.$2.historical) return a.$2.historical ? 1 : -1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, hit) in indexed) hit.toPlace()];
}

/// Closest official name within 1 km of a point search, or null.
String? closestSsrName(Object? body, {int maxMeters = 1000}) {
  final hits = [
    for (final hit in _readSsr(body, searchShape: false))
      if (hit.meters != null && hit.meters! <= maxMeters) hit,
  ];
  if (hits.isEmpty) return null;
  hits.sort((a, b) {
    if (a.historical != b.historical) return a.historical ? 1 : -1;
    return a.meters!.compareTo(b.meters!);
  });
  return hits.first.name;
}

List<SsrHit> _readSsr(Object? body, {required bool searchShape}) {
  if (body is! Map) return [];
  final navn = body['navn'];
  if (navn is! List) return [];
  final out = <SsrHit>[];
  for (final raw in navn) {
    if (raw is! Map) continue;
    final el = Map<String, dynamic>.from(raw);
    final point = el['representasjonspunkt'];
    if (point is! Map) continue;
    final lat = point['nord'];
    final lon = point['øst'];
    if (lat is! num || lon is! num) continue;
    final written = _writtenForm(el, searchShape: searchShape);
    if (written == null) continue;
    final kommuner = el['kommuner'];
    final fylker = el['fylker'];
    final kommune = kommuner is List && kommuner.isNotEmpty && kommuner.first is Map
        ? '${(kommuner.first as Map)['kommunenavn'] ?? ''}'.trim()
        : '';
    final fylke = fylker is List && fylker.isNotEmpty && fylker.first is Map
        ? '${(fylker.first as Map)['fylkesnavn'] ?? ''}'.trim()
        : '';
    final meters = el['meterFraPunkt'];
    out.add(
      SsrHit(
        name: written.$1,
        type: (el['navneobjekttype'] as String?)?.trim() ?? '',
        kommune: kommune,
        fylke: fylke,
        point: LatLng(lat.toDouble(), lon.toDouble()),
        historical:
            el['stedstatus'] == 'relikt' ||
            written.$2 == 'historisk' ||
            (written.$3).contains('historisk'),
        meters: meters is num ? meters.round() : null,
      ),
    );
  }
  return out;
}

/// Name, name-status, spelling-status.
(String, String, String)? _writtenForm(
  Map<String, dynamic> el, {
  required bool searchShape,
}) {
  if (searchShape) {
    final name = (el['skrivemåte'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return (
      name,
      (el['navnestatus'] as String?)?.trim() ?? '',
      (el['skrivemåtestatus'] as String?)?.trim() ?? '',
    );
  }
  final forms = el['stedsnavn'];
  if (forms is! List || forms.isEmpty) return null;
  Map<String, dynamic>? best;
  for (final raw in forms) {
    if (raw is! Map) continue;
    final form = Map<String, dynamic>.from(raw);
    final status = (form['skrivemåtestatus'] as String?) ?? '';
    if (status.contains('prioritert')) {
      best = form;
      break;
    }
    best ??= form;
  }
  if (best == null) return null;
  final name = (best['skrivemåte'] as String?)?.trim() ?? '';
  if (name.isEmpty) return null;
  return (
    name,
    (best['navnestatus'] as String?)?.trim() ?? '',
    (best['skrivemåtestatus'] as String?)?.trim() ?? '',
  );
}
