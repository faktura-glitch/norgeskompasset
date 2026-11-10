import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'weather_service.dart' show ServiceException;

/// OSM tourism value for a mountain hut.
enum HutKind { staffed, unstaffed }

/// One tourist hut from OpenStreetMap. Same source datakart.no uses
/// for its hut map: `tourism=alpine_hut` and `tourism=wilderness_hut`.
/// Data © OpenStreetMap contributors, ODbL.
class TouristHut {
  final String id;
  final String name;
  final HutKind kind;
  final LatLng point;
  final double? elevation;
  final String operator;
  final String capacity;
  final String openingHours;

  const TouristHut({
    required this.id,
    required this.name,
    required this.kind,
    required this.point,
    this.elevation,
    this.operator = '',
    this.capacity = '',
    this.openingHours = '',
  });

  String get kindLabel => switch (kind) {
    HutKind.staffed => 'Betjent i sesong',
    HutKind.unstaffed => 'Ubetjent',
  };
}

/// Tourist huts shipped with the app.
///
/// OpenStreetMap's hut register does not allow browser calls, so the
/// map reads a snapshot taken from Overpass (alpine_hut and
/// wilderness_hut in Norway) instead of asking the network each time.
class HutService {
  static List<TouristHut>? _catalog;

  Future<List<TouristHut>> fetchInBounds(
    double south,
    double west,
    double north,
    double east,
  ) async {
    final all = await _load();
    return [
      for (final hut in all)
        if (hut.point.latitude >= south &&
            hut.point.latitude <= north &&
            hut.point.longitude >= west &&
            hut.point.longitude <= east)
          hut,
    ];
  }

  static Future<List<TouristHut>> _load() async {
    final cached = _catalog;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/huts.json');
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const ServiceException('Hytteregisteret kunne ikke leses.');
    }
    final out = <TouristHut>[
      for (final row in decoded)
        if (row is List) ?hutFromCompact(row),
    ];
    _catalog = out;
    return out;
  }
}

/// One compact snapshot row:
/// `[name, lat, lon, kind 1/0, ele|null, operator, capacity, openingHours]`.
/// Operator, capacity and opening hours are empty when the snapshot has no value.
TouristHut? hutFromCompact(List row) {
  if (row.length < 4) return null;
  final lat = row[1];
  final lon = row[2];
  if (lat is! num || lon is! num) return null;
  String textAt(int index) {
    if (row.length <= index || row[index] == null) return '';
    return '${row[index]}'.trim();
  }

  final name = '${row[0]}'.trim();
  return TouristHut(
    id: '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}',
    name: name.isEmpty ? 'Hytte uten navn' : name,
    kind: row[3] == 1 ? HutKind.staffed : HutKind.unstaffed,
    point: LatLng(lat.toDouble(), lon.toDouble()),
    elevation: row.length > 4 && row[4] is num ? (row[4] as num).toDouble() : null,
    operator: textAt(5),
    capacity: textAt(6),
    openingHours: textAt(7),
  );
}

/// Parses an Overpass JSON document. Public so tests can use a fixture
/// without calling the network.
List<TouristHut> parseHuts(Object? body) {
  final map = body as Map<String, dynamic>;
  final elements = map['elements'] as List? ?? [];
  final out = <TouristHut>[];
  for (final raw in elements) {
    final el = Map<String, dynamic>.from(raw as Map);
    final tags = Map<String, dynamic>.from(el['tags'] as Map? ?? {});
    final tourism = tags['tourism'] as String? ?? '';
    final kind = switch (tourism) {
      'alpine_hut' => HutKind.staffed,
      'wilderness_hut' => HutKind.unstaffed,
      _ => null,
    };
    if (kind == null) continue;
    double? coord(Object? value) => value is num ? value.toDouble() : null;
    final center = el['center'] as Map?;
    final lat = coord(el['lat']) ?? coord(center?['lat']);
    final lon = coord(el['lon']) ?? coord(center?['lon']);
    if (lat == null || lon == null) continue;
    final name = (tags['name'] as String?)?.trim() ?? '';
    out.add(
      TouristHut(
        id: '${el['type']}/${el['id']}',
        name: name.isEmpty ? 'Hytte uten navn' : name,
        kind: kind,
        point: LatLng(lat, lon),
        elevation: double.tryParse('${tags['ele'] ?? ''}'),
        operator: (tags['operator'] as String?)?.trim() ?? '',
        capacity: (tags['capacity'] as String?)?.trim() ?? '',
        openingHours: (tags['opening_hours'] as String?)?.trim() ?? '',
      ),
    );
  }
  return out;
}
