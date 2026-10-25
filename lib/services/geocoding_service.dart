import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'weather_service.dart' show ServiceException, describeNetworkError;

class PlaceResult {
  final String name;
  final String displayName;
  final String type;
  final LatLng point;

  const PlaceResult({
    required this.name,
    required this.displayName,
    required this.type,
    required this.point,
  });
}

/// Place search via OpenStreetMap Nominatim, restricted to Norway.
/// Free public service — keep request volume low (search-as-you-type
/// is debounced by callers).
class GeocodingService {
  static const _endpoint = 'https://nominatim.openstreetmap.org/search';

  Future<List<PlaceResult>> search(String query) async {
    if (query.trim().length < 2) return [];
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'format': 'jsonv2',
      'q': query,
      'countrycodes': 'no',
      'limit': '6',
      'accept-language': 'nb',
    });
    http.Response res;
    try {
      res = await http.get(uri, headers: {
        if (!kIsWeb) 'User-Agent': 'NorgesKompasset/1.0 (hiking planner)',
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      throw ServiceException(
          'Fikk ikke kontakt med stedssøket (${describeNetworkError(e)}).');
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
      );
    }).toList();
  }
}
