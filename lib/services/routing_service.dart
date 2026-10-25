import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_models.dart';
import 'weather_service.dart' show ServiceException, describeNetworkError;

/// Result of a route calculation: the ordered points plus how many
/// legs were actually routed along trails.
typedef RouteResult = ({
  List<RoutePoint> points,
  int routedLegs,
  int totalLegs,

  /// Inclusive index ranges into [points] that came from straight-line
  /// legs (explicitly chosen or unroutable fallback) — used to draw
  /// those stretches differently from verified trail sections.
  List<({int start, int end})> straightRanges,
});

/// Hiking routing via the public BRouter service (brouter.de),
/// using the 'hiking-mountain' profile which follows mapped trails
/// (OpenStreetMap data).
///
/// Routing is attempted per leg between consecutive anchor points, so
/// one unroutable leg degrades only that segment to a straight-line
/// estimate instead of the whole route.
class RoutingService {
  static const _endpoint = 'https://brouter.de/brouter';

  /// Profile for foot travel — follows mapped hiking trails.
  static const profileHiking = 'hiking-mountain';

  /// Profile for ski tours. The public BRouter instance has no
  /// dedicated ski profile; 'trekking' also follows tracks and the
  /// ways that carry mapped nordic pistes (OSM piste:type=nordic).
  static const profileSki = 'trekking';

  /// Profile for bike trips — follows roads, cycleways and tracks.
  static const profileBike = 'fastbike';

  /// Profile for canoe/kayak legs — follows OSM waterways.
  static const profilePaddle = 'river';

  /// Routes each leg between consecutive anchors via BRouter.
  /// Legs that cannot be trail-routed fall back to straight lines.
  /// Throws [ServiceException] only when the service itself is
  /// unreachable (so the caller can still report the outage).
  /// [straightLegs] contains leg indices (anchor i-1 → anchor i) that
  /// the user explicitly wants drawn straight — those legs never hit
  /// the routing service and count as unrouted in the result.
  /// [profile] selects the BRouter profile (see [profileHiking] /
  /// [profileSki]).
  Future<RouteResult> routeAlongTrails(List<LatLng> anchors,
      {Set<int>? straightLegs, String profile = profileHiking}) async {
    if (anchors.length < 2) {
      return (
        points: <RoutePoint>[],
        routedLegs: 0,
        totalLegs: 0,
        straightRanges: const <({int start, int end})>[],
      );
    }
    final totalLegs = anchors.length - 1;
    var routedLegs = 0;
    final out = <RoutePoint>[];
    final straightRanges = <({int start, int end})>[];
    var unreachable = false;

    for (var i = 1; i < anchors.length; i++) {
      List<RoutePoint> legPoints;
      var straight = false;
      if (straightLegs?.contains(i) == true) {
        legPoints = _straight(anchors[i - 1], anchors[i]);
        straight = true;
      } else {
        final leg = [anchors[i - 1], anchors[i]];
        try {
          legPoints = await _request(leg, profile);
          routedLegs++;
        } on ServiceException catch (e) {
          if (e.message.contains('nett')) unreachable = true;
          legPoints = _straight(anchors[i - 1], anchors[i]);
          straight = true;
        }
      }
      // Avoid duplicating the shared boundary point between legs.
      if (out.isNotEmpty && legPoints.isNotEmpty) legPoints.removeAt(0);
      if (straight && legPoints.isNotEmpty) {
        straightRanges.add((start: out.length, end: out.length + legPoints.length - 1));
      }
      out.addAll(legPoints);
    }

    if (routedLegs == 0 && unreachable) {
      throw const ServiceException(
          'Fikk ikke kontakt med ruteberegneren (BRouter).');
    }
    return (
      points: out,
      routedLegs: routedLegs,
      totalLegs: totalLegs,
      straightRanges: straightRanges,
    );
  }

  Future<List<RoutePoint>> _request(List<LatLng> anchors,
      String profile) async {
    final lonlats = anchors
        .map((p) =>
            '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join('|');
    final uri = Uri.parse(
        '$_endpoint?lonlats=$lonlats&profile=$profile&alternativeidx=0&format=geojson');

    http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw ServiceException(
          'Fikk ikke kontakt med ruteberegneren (${describeNetworkError(e)}).');
    }
    if (res.statusCode != 200) {
      throw ServiceException(
          'Ruteberegner svarte med feil (HTTP ${res.statusCode}).');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final features = body['features'] as List? ?? [];
    if (features.isEmpty) {
      throw const ServiceException('Ingen stirute funnet for etappen.');
    }
    final geometry =
        features.first['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List? ?? [];
    final points = <RoutePoint>[];
    for (final c in coords) {
      final list = c as List;
      if (list.length >= 2) {
        points.add(RoutePoint(
          (list[1] as num).toDouble(),
          (list[0] as num).toDouble(),
          elevation: list.length >= 3 ? (list[2] as num?)?.toDouble() : null,
        ));
      }
    }
    if (points.length < 2) {
      throw const ServiceException('Ingen stirute funnet for etappen.');
    }
    return points;
  }

  List<RoutePoint> _straight(LatLng a, LatLng b) {
    const steps = 12;
    final points = <RoutePoint>[RoutePoint(a.latitude, a.longitude)];
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      points.add(RoutePoint(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ));
    }
    return points;
  }

  /// Straight-line fallback for a whole set of anchors — always
  /// marked estimated by callers.
  List<RoutePoint> straightLine(List<LatLng> anchors) {
    final points = <RoutePoint>[];
    for (var i = 1; i < anchors.length; i++) {
      final seg = _straight(anchors[i - 1], anchors[i]);
      if (points.isNotEmpty && seg.isNotEmpty) seg.removeAt(0);
      points.addAll(seg);
    }
    return points;
  }
}
