import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../core/http_identity.dart';
import '../models/avalanche.dart';
import 'weather_service.dart' show ServiceException;

/// Avalanche warnings from NVE's Varsom API — the same data shown on
/// varsom.no. Free to use; NVE asks that warnings are attributed to
/// "Snøskredvarslingen i Norge og www.varsom.no".
///
/// Warnings exist only for the avalanche season (~Nov–Jun) and are
/// published a few days ahead — queries outside that window return
/// an empty list, never an error to show the user.
class VarsomService {
  static const _base =
      'https://api01.nve.no/hydrology/forecast/avalanche/v6.3.0/api';

  /// Fetches simple avalanche warnings for [lat],[lon] covering
  /// [from]–[to] (inclusive dates, Norwegian language).
  Future<List<AvalancheWarning>> fetchWarnings(
      double lat, double lon, DateTime from, DateTime to) async {
    String d(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final url =
        '$_base/AvalancheWarningByCoordinates/Simple/$lat/$lon/1/${d(from)}/${d(to)}';
    http.Response res;
    try {
      res = await http.get(Uri.parse(url), headers: const {
        'Accept': 'application/json',
        if (!kIsWeb) 'User-Agent': kUserAgent,
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ServiceException(
          'Fikk ikke kontakt med skredvarslingen ($e)');
    }
    if (res.statusCode != 200) {
      throw ServiceException(
          'Skredvarslingen svarte med feil (${res.statusCode})');
    }
    final body = res.body.trim();
    // Outside the warning season the API returns literal 'null'.
    if (body.isEmpty || body == 'null') return const [];
    final parsed = jsonDecode(body);
    if (parsed is! List) return const [];
    return parsed
        .whereType<Map>()
        .map((j) => AvalancheWarning.fromVarsomJson(
            Map<String, dynamic>.from(j), lat, lon))
        .toList();
  }
}
