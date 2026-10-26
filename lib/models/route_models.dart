import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// A single coordinate on a route. [elevation] is in meters and may be null
/// when elevation data has not been fetched or is unavailable.
class RoutePoint {
  final double lat;
  final double lon;
  double? elevation;

  RoutePoint(this.lat, this.lon, {this.elevation});

  LatLng get latLng => LatLng(lat, lon);

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    if (elevation != null) 'ele': elevation,
  };

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
    (j['lat'] as num).toDouble(),
    (j['lon'] as num).toDouble(),
    elevation: (j['ele'] as num?)?.toDouble(),
  );
}

enum WaypointType { start, end, waypoint, overnight }

enum RouteSource {
  /// All legs routed along known hiking trails by the routing engine.
  trail,

  /// Some legs follow trails; other legs are straight-line estimates.
  mixed,

  /// Drawn/pinned manually by the user; not verified against trail data.
  manual,

  /// Straight-line or snapped estimate; accuracy not verified.
  estimated,
}

/// Labels the planner gives points before a real place name is known.
bool isGenericWaypointName(String name) {
  final n = name.trim();
  return n.isEmpty ||
      n == 'Start (A)' ||
      n == 'Mål (B)' ||
      n == 'Punkt' ||
      n == 'Overnatting' ||
      n.startsWith('Via-punkt');
}

/// Trip name from the route's start and goal, e.g. «Stavsro – Gaustatoppen».
/// Returns '' when neither point has a real place name.
String suggestTripName(List<Waypoint> waypoints) {
  String? named(WaypointType type) {
    final w = waypoints.where((w) => w.type == type).firstOrNull;
    return w == null || isGenericWaypointName(w.name) ? null : w.name.trim();
  }

  final start = named(WaypointType.start);
  final end = named(WaypointType.end);
  if (start != null && end != null) {
    return start == end ? 'Rundtur fra $start' : '$start – $end';
  }
  return start ?? end ?? '';
}

class Waypoint {
  final String id;
  String name;
  // Mutable so a waypoint can be repositioned on the map (move mode).
  double lat;
  double lon;
  WaypointType type;

  /// When true, the leg *ending* at this waypoint is drawn as a
  /// straight line instead of being trail-routed — useful across
  /// terrain with no mapped trail (ridges, lakes, off-trail).
  bool straightLeg;

  Waypoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.type,
    this.straightLeg = false,
  });

  LatLng get latLng => LatLng(lat, lon);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lon': lon,
    'type': type.name,
    'straightLeg': straightLeg,
  };

  factory Waypoint.fromJson(Map<String, dynamic> j) => Waypoint(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    type: WaypointType.values.asNameMap()[j['type']] ?? WaypointType.waypoint,
    straightLeg: j['straightLeg'] as bool? ?? false,
  );
}

/// An ordered hiking route between a start and a destination.
class HikingRoute {
  /// Ordered points making up the route polyline.
  List<RoutePoint> points;
  List<Waypoint> waypoints;
  RouteSource source;

  /// Total distance in meters (computed from [points]).
  double distanceMeters;
  double totalAscent;
  double totalDescent;
  double? highestPoint;

  /// Inclusive index ranges into [points] that are straight-line
  /// segments rather than verified trail sections. Lets the map draw
  /// estimated legs distinctly. Empty for fully trail-routed or
  /// imported routes.
  List<({int start, int end})> straightRanges;

  /// Index of the turning point when the route is «tur-retur» (the
  /// points after it mirror the way out). Null for one-way routes.
  int? turnIndex;

  HikingRoute({
    this.points = const [],
    this.waypoints = const [],
    this.source = RouteSource.estimated,
    this.distanceMeters = 0,
    this.totalAscent = 0,
    this.totalDescent = 0,
    this.highestPoint,
    this.straightRanges = const [],
    this.turnIndex,
  });

  bool get hasRoute => points.length >= 2;

  bool get outAndBack => turnIndex != null;

  /// Appends the way back (same path, reversed) so distance, time,
  /// stages, profile and packing cover the whole trip. No-op when the
  /// route is already out-and-back.
  void makeOutAndBack() {
    if (outAndBack || points.length < 2) return;
    final last = points.length - 1;
    points = [
      ...points,
      for (var i = last - 1; i >= 0; i--)
        RoutePoint(
          points[i].lat,
          points[i].lon,
          elevation: points[i].elevation,
        ),
    ];
    straightRanges = [
      ...straightRanges,
      for (final r in straightRanges)
        (start: 2 * last - r.end, end: 2 * last - r.start),
    ];
    turnIndex = last;
    distanceMeters *= 2;
  }

  /// Drops the mirrored way back again.
  void makeOneWay() {
    final t = turnIndex;
    if (t == null) return;
    points = points.sublist(0, t + 1);
    straightRanges = [
      for (final r in straightRanges)
        if (r.end <= t) r,
    ];
    turnIndex = null;
    distanceMeters /= 2;
  }

  /// Deviation alerts are only meaningful for a wholly trail-routed line.
  /// Imported, manual and straight-line legs have no verified corridor.
  bool get supportsDeviationAlerts =>
      hasRoute && source == RouteSource.trail && straightRanges.isEmpty;

  LatLng? get start => points.isEmpty ? null : points.first.latLng;
  LatLng? get end => points.isEmpty ? null : points.last.latLng;

  // Derived geometry is memoized — the point list is only ever
  // replaced wholesale (build/import), never mutated in place, so
  // identity is a safe invalidation key. Map screens rebuild often.
  List<LatLng>? _latLngCache;
  List<({List<LatLng> points, bool straight})>? _segCache;
  List<RoutePoint>? _cacheFor;

  List<LatLng> get latLngs {
    if (!identical(_cacheFor, points)) _invalidate();
    return _latLngCache ??= points.map((p) => p.latLng).toList();
  }

  void _invalidate() {
    _cacheFor = points;
    _latLngCache = null;
    _segCache = null;
  }

  /// Splits the route into consecutive polyline pieces, each marked
  /// straight (estimated) or trail. Routes without recorded
  /// [straightRanges] fall back to a single piece styled by [source].
  List<({List<LatLng> points, bool straight})> polylineSegments() {
    if (!identical(_cacheFor, points)) _invalidate();
    return _segCache ??= _buildSegments();
  }

  List<({List<LatLng> points, bool straight})> _buildSegments() {
    if (points.length < 2) return const [];
    if (straightRanges.isEmpty) {
      return [(points: latLngs, straight: source != RouteSource.trail)];
    }
    final ranges = [...straightRanges]
      ..sort((a, b) => a.start.compareTo(b.start));
    final segs = <({List<LatLng> points, bool straight})>[];
    var cursor = 0;
    for (final r in ranges) {
      final s = r.start.clamp(0, points.length - 1);
      final e = r.end.clamp(0, points.length - 1);
      if (s > cursor) {
        segs.add((
          points: [for (var i = cursor; i <= s; i++) points[i].latLng],
          straight: false,
        ));
      }
      segs.add((
        points: [for (var i = s; i <= e; i++) points[i].latLng],
        straight: true,
      ));
      cursor = e;
    }
    if (cursor < points.length - 1) {
      segs.add((
        points: [for (var i = cursor; i < points.length; i++) points[i].latLng],
        straight: false,
      ));
    }
    return segs;
  }

  String get sourceLabel => switch (source) {
    RouteSource.trail => 'Beregnet langs kjente stier',
    RouteSource.mixed => 'Delvis langs stier – enkelte partier er estimert',
    RouteSource.manual => 'Manuelt tegnet rute',
    RouteSource.estimated => 'Estimert rute (ikke verifisert mot sti)',
  };

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
    'waypoints': waypoints.map((w) => w.toJson()).toList(),
    'source': source.name,
    'distanceMeters': distanceMeters,
    'totalAscent': totalAscent,
    'totalDescent': totalDescent,
    'highestPoint': highestPoint,
    if (turnIndex != null) 'turnIndex': turnIndex,
    if (straightRanges.isNotEmpty)
      'straightRanges': [
        for (final r in straightRanges) [r.start, r.end],
      ],
  };

  factory HikingRoute.fromJson(Map<String, dynamic> j) {
    final route = HikingRoute(
      points: (j['points'] as List? ?? [])
          .map((p) => RoutePoint.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      waypoints: (j['waypoints'] as List? ?? [])
          .map((w) => Waypoint.fromJson(Map<String, dynamic>.from(w)))
          .toList(),
      source:
          RouteSource.values.asNameMap()[j['source']] ?? RouteSource.estimated,
      distanceMeters: (j['distanceMeters'] as num?)?.toDouble() ?? 0,
      totalAscent: (j['totalAscent'] as num?)?.toDouble() ?? 0,
      totalDescent: (j['totalDescent'] as num?)?.toDouble() ?? 0,
      highestPoint: (j['highestPoint'] as num?)?.toDouble(),
      turnIndex: (j['turnIndex'] as num?)?.toInt(),
      straightRanges: [
        for (final r in j['straightRanges'] as List? ?? [])
          (start: (r[0] as num).toInt(), end: (r[1] as num).toInt()),
      ],
    );
    // Index ranges are tied to the point list — drop any that no
    // longer fit (e.g. written before a point edit/GPX re-import).
    final n = route.points.length;
    route.straightRanges = [
      for (final r in route.straightRanges)
        if (r.start >= 0 && r.start <= r.end && r.end < n) r,
    ];
    final t = route.turnIndex;
    if (t != null && (t < 1 || t >= n - 1)) route.turnIndex = null;
    return route;
  }

  String encode() => jsonEncode(toJson());
  factory HikingRoute.decode(String s) => HikingRoute.fromJson(jsonDecode(s));

  /// Compact sync format (v2): points as [lat, lon, ele?] arrays with
  /// coordinates rounded to ~1 m precision and elevation to ~10 cm —
  /// far smaller than the full object-per-point JSON, still enough to
  /// redraw the route and rebuild stages on another device.
  Map<String, dynamic> toCompactJson() {
    double r6(double v) => (v * 1e6).round() / 1e6;
    return {
      'src': source.name,
      'dist': distanceMeters.round(),
      'asc': totalAscent.round(),
      'desc': totalDescent.round(),
      if (highestPoint != null) 'high': highestPoint!.round(),
      if (turnIndex != null) 'turn': turnIndex,
      'pts': [
        for (final p in points)
          p.elevation == null
              ? [r6(p.lat), r6(p.lon)]
              : [r6(p.lat), r6(p.lon), (p.elevation! * 10).round() / 10],
      ],
      if (waypoints.isNotEmpty)
        'wps': waypoints.map((w) => w.toJson()).toList(),
      if (straightRanges.isNotEmpty)
        'straight': [
          for (final r in straightRanges) [r.start, r.end],
        ],
    };
  }

  factory HikingRoute.fromCompactJson(Map<String, dynamic> j) {
    final route = HikingRoute(
      points: [
        for (final p in j['pts'] as List? ?? [])
          RoutePoint(
            (p[0] as num).toDouble(),
            (p[1] as num).toDouble(),
            elevation: p.length > 2 ? (p[2] as num).toDouble() : null,
          ),
      ],
      waypoints: (j['wps'] as List? ?? [])
          .map((w) => Waypoint.fromJson(Map<String, dynamic>.from(w)))
          .toList(),
      source: RouteSource.values.asNameMap()[j['src']] ?? RouteSource.estimated,
      distanceMeters: (j['dist'] as num?)?.toDouble() ?? 0,
      totalAscent: (j['asc'] as num?)?.toDouble() ?? 0,
      totalDescent: (j['desc'] as num?)?.toDouble() ?? 0,
      highestPoint: (j['high'] as num?)?.toDouble(),
      turnIndex: (j['turn'] as num?)?.toInt(),
      straightRanges: [
        for (final r in j['straight'] as List? ?? [])
          (start: (r[0] as num).toInt(), end: (r[1] as num).toInt()),
      ],
    );
    final n = route.points.length;
    route.straightRanges = [
      for (final r in route.straightRanges)
        if (r.start >= 0 && r.start <= r.end && r.end < n) r,
    ];
    return route;
  }
}
