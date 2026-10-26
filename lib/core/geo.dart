import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';

const _distance = Distance();

/// Mid-anchor positions for an approximate [targetKm] loop starting
/// and ending at [start]. Two waypoints on bearings rotated by
/// [seed] form a rough triangle; trail routing typically comes out
/// ~20 % longer than the polygon perimeter, so the radius is reduced
/// to compensate. Different seeds rotate the loop — re-roll for a
/// new suggestion.
List<LatLng> loopAnchors(LatLng start, double targetKm, int seed) {
  const mPerDegLat = 111320.0;
  final radius = targetKm * 1000 / 3.2;
  final base = (seed * 67.0) % 360;
  final cosLat = cos(start.latitude * pi / 180).clamp(0.3, 1.0);
  return [
    for (final b in [base, base + 120])
      LatLng(
        start.latitude + radius * cos(b * pi / 180) / mPerDegLat,
        start.longitude + radius * sin(b * pi / 180) / (mPerDegLat * cosLat),
      ),
  ];
}

/// Haversine distance in meters between two points.
double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

/// Total length in meters of an ordered point list.
double routeDistanceMeters(List<RoutePoint> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += metersBetween(points[i - 1].latLng, points[i].latLng);
  }
  return sum;
}

/// Cumulative distance in meters at each point index.
List<double> cumulativeDistances(List<RoutePoint> points) {
  final out = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    out[i] = out[i - 1] + metersBetween(points[i - 1].latLng, points[i].latLng);
  }
  return out;
}

/// Ascent/descent computed from point elevations.
/// A small threshold filters typical elevation-data noise (≈3 m per step).
({double ascent, double descent, double? highest}) elevationStats(
  List<RoutePoint> points, {
  double noiseThresholdMeters = 3.0,
}) {
  var ascent = 0.0, descent = 0.0, pending = 0.0;
  double? lastEle;
  double? highest;
  for (final p in points) {
    final e = p.elevation;
    if (e == null) continue;
    if (highest == null || e > highest) highest = e;
    if (lastEle == null) {
      lastEle = e;
      continue;
    }
    pending += e - lastEle;
    if (pending.abs() >= noiseThresholdMeters) {
      if (pending > 0) {
        ascent += pending;
      } else {
        descent += -pending;
      }
      pending = 0;
    }
    lastEle = e;
  }
  return (ascent: ascent, descent: descent, highest: highest);
}

/// Estimated hiking time in minutes using Naismith's rule
/// (5 km/h + 10 min per 100 m ascent), adjusted for descent steepness
/// and the user's pace. This is an estimate, not a guarantee.
/// Estimated travel minutes. Base speed and terrain penalties vary
/// by activity — Naismith's rule (5 km/h + 10 min/100 m ascent) is
/// the foot baseline; ski is slower uphill on fells, bike much
/// faster on the flat but still punished by climbing, and paddling
/// ignores elevation entirely (flat water by definition).
double estimateHikingMinutes(
  double distanceMeters,
  double ascentMeters,
  double descentMeters,
  HikingPace pace, {
  TripActivity activity = TripActivity.foot,
  bool withChildren = false,
}) {
  final km = distanceMeters / 1000;
  final (kmh, minPer100m) = switch (activity) {
    TripActivity.foot => (5.0, 10.0),
    TripActivity.run => (9.0, 8.0),
    TripActivity.ski => (6.0, 12.0),
    TripActivity.bike => (14.0, 15.0),
    TripActivity.paddle => (5.0, 0.0),
  };
  var minutes = km / kmh * 60 + ascentMeters / 100 * minPer100m;
  // Steep descents slow hikers, runners and skiers — not paddlers or
  // riders.
  if (km > 0 && (activity.onFoot || activity == TripActivity.ski)) {
    final descentPerKm = descentMeters / km;
    if (descentPerKm > 40) {
      minutes += descentMeters / 100 * 2;
    }
  }
  // Groups with children stop more and walk shorter steps — roughly a
  // third slower than the adult pace.
  return minutes * pace.timeFactor * (withChildren ? 1.3 : 1.0);
}

/// Share of the route length (0–1) that has elevation data, measured
/// along the distance — not by counting points. Elevation is fetched
/// for an even sample of ~200 points and the rest are left empty on
/// purpose, so a point count would call a fully covered route "61 %".
/// A stretch between two elevated points counts as covered unless the
/// gap is implausibly long (over 500 m or 2 % of the route).
double elevationCoverage(List<RoutePoint> points) {
  if (points.length < 2) return 0;
  final cum = cumulativeDistances(points);
  final total = cum.last;
  if (total <= 0) return 0;
  final maxGap = max(500.0, total * 0.02);
  var covered = 0.0;
  int? last;
  for (var i = 0; i < points.length; i++) {
    if (points[i].elevation == null) continue;
    if (last != null) {
      final gap = cum[i] - cum[last];
      if (gap <= maxGap) covered += gap;
    }
    last = i;
  }
  return (covered / total).clamp(0.0, 1.0);
}

/// Days a trip should be spread over so no day exceeds a sensible
/// moving-time budget: 8 h for adults, 6 h with children. Breaks come
/// on top, so the budget is deliberately conservative. Returns 1 when
/// the trip fits in a day.
int recommendedTripDays(num totalMinutes, {bool withChildren = false}) {
  if (totalMinutes <= 0) return 1;
  final budget = (withChildren ? 6 : 8) * 60;
  return (totalMinutes / budget).ceil().clamp(1, 14);
}

/// Index at which a new via point tapped at [p] belongs in [anchors]
/// (the anchor ending the leg closest to [p]), so the route keeps
/// following the map instead of always squeezing in before the goal.
/// Returns [anchors.length] (append) with fewer than two anchors.
int nearestLegIndex(List<LatLng> anchors, LatLng p) {
  if (anchors.length < 2) return anchors.length;
  var best = 1;
  var bestD = double.infinity;
  for (var i = 1; i < anchors.length; i++) {
    final d = _segmentDistanceMeters(anchors[i - 1], anchors[i], p);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Distance from [p] to the segment a–b on a local flat projection —
/// plenty accurate for leg lengths of a few tens of km.
double _segmentDistanceMeters(LatLng a, LatLng b, LatLng p) {
  final k = cos(p.latitude * pi / 180) * 111320;
  double x(LatLng q) => (q.longitude - p.longitude) * k;
  double y(LatLng q) => (q.latitude - p.latitude) * 110540;
  final ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return sqrt(cx * cx + cy * cy);
}

/// Splits [points] into [count] stages of roughly equal distance.
/// Stage boundaries snap to the nearest existing route point.
List<List<RoutePoint>> splitIntoStages(List<RoutePoint> points, int count) {
  if (points.length < 2 || count < 1) return [];
  count = min(count, points.length);
  if (count == 1) return [points];
  final cum = cumulativeDistances(points);
  final total = cum.last;
  if (total <= 0) return [points];

  final result = <List<RoutePoint>>[];
  var startIdx = 0;
  for (var s = 1; s <= count; s++) {
    final target = total * s / count;
    var endIdx = startIdx;
    for (var i = startIdx; i < points.length; i++) {
      endIdx = i;
      if (cum[i] >= target) break;
    }
    if (s == count) endIdx = points.length - 1;
    result.add(points.sublist(startIdx, endIdx + 1));
    startIdx = endIdx;
  }
  return result.where((l) => l.isNotEmpty).toList();
}

/// Splits points at the given boundary indices (exclusive boundaries).
/// Each returned stage shares the boundary point with its neighbours.
List<List<RoutePoint>> splitAtIndices(
  List<RoutePoint> points,
  List<int> boundaries,
) {
  final result = <List<RoutePoint>>[];
  var start = 0;
  for (final b in boundaries) {
    if (b > start && b < points.length) {
      result.add(points.sublist(start, b + 1));
      start = b;
    }
  }
  result.add(points.sublist(start));
  return result.where((l) => l.isNotEmpty).toList();
}

/// Documented difficulty scoring for one stage.
///
/// Score components (0-100 scale, capped):
/// - distance:   up to 40 pts (2.4 pts/km, cap at ~17 km)
/// - ascent:     up to 30 pts (0.06 pts/m, cap at 500 m)
/// - descent:    up to 10 pts (0.02 pts/m; steep descents cost energy)
/// - steepness:  up to 20 pts based on max sustained gradient sections
///
/// Bands: <25 easy, <45 moderate, <65 challenging, >=65 demanding.
StageDifficulty analyzeStageDifficulty(Stage stage) {
  final km = stage.distanceMeters / 1000;
  final factors = <String>[];

  var distanceScore = km * 2.4;
  if (km >= 15) {
    factors.add('Lang etappe (${km.toStringAsFixed(1)} km)');
  } else if (km >= 8) {
    factors.add('Moderat distanse (${km.toStringAsFixed(1)} km)');
  }
  distanceScore = min(distanceScore, 40);

  var ascentScore = stage.ascent * 0.06;
  if (stage.ascent >= 800) {
    factors.add('Stor stigning (+${stage.ascent.round()} moh)');
  } else if (stage.ascent >= 300) {
    factors.add('Merkbare stigninger (+${stage.ascent.round()} moh)');
  }
  ascentScore = min(ascentScore, 30);

  var descentScore = stage.descent * 0.02;
  if (stage.descent >= 800) {
    factors.add('Lang nedstigning (-${stage.descent.round()} m) – belastende');
  } else if (stage.descent >= 400) {
    factors.add('Merkbare nedstigninger (-${stage.descent.round()} m)');
  }
  descentScore = min(descentScore, 10);

  var steepScore = 0.0;
  final steep = maxSustainedGradient(stage.points);
  if (steep != null && steep.percent > 25) {
    steepScore = 20;
    factors.add(
      'Bratte partier (inntil ${steep.percent.round()} % stigning over ${(steep.distanceMeters).round()} m)',
    );
  } else if (steep != null && steep.percent > 15) {
    steepScore = 10;
    factors.add('Enkelte bratte partier (inntil ${steep.percent.round()} %)');
  }

  if (stage.estimatedMinutes > 480) {
    factors.add(
      'Lang dag ute (${(stage.estimatedMinutes / 60).toStringAsFixed(1)} t estimert)',
    );
  }

  final score = (distanceScore + ascentScore + descentScore + steepScore).clamp(
    0,
    100,
  );
  final level = score < 25
      ? DifficultyLevel.easy
      : score < 45
      ? DifficultyLevel.moderate
      : score < 65
      ? DifficultyLevel.challenging
      : DifficultyLevel.demanding;

  if (factors.isEmpty) {
    factors.add('Rolig terreng og kort distanse');
  }
  return StageDifficulty(
    level: level,
    score: score.toDouble(),
    factors: factors,
  );
}

/// Finds the maximum sustained gradient (percent) over >=150 m sections.
({double percent, double distanceMeters})? maxSustainedGradient(
  List<RoutePoint> points, {
  double windowMeters = 150,
}) {
  if (points.length < 2) return null;
  final cum = cumulativeDistances(points);
  double? best;
  var bestDist = 0.0;
  var start = 0;
  for (var end = 1; end < points.length; end++) {
    while (cum[end] - cum[start] > windowMeters && start < end - 1) {
      start++;
    }
    final d = cum[end] - cum[start];
    final e0 = points[start].elevation;
    final e1 = points[end].elevation;
    if (d >= windowMeters * 0.6 && e0 != null && e1 != null) {
      final grade = (e1 - e0) / d * 100;
      if (best == null || grade.abs() > best.abs()) {
        best = grade;
        bestDist = d;
      }
    }
  }
  if (best == null) return null;
  return (percent: best, distanceMeters: bestDist);
}

/// Perpendicular distance in meters from [position] to the polyline —
/// not just to the nearest vertex. Matters on sparse routes where
/// consecutive points can be far apart (straight-line legs).
double distanceToRouteMeters(List<RoutePoint> points, LatLng position) {
  if (points.isEmpty) return double.infinity;
  if (points.length == 1) {
    return metersBetween(points.first.latLng, position);
  }
  // Local flat approximation around the position is plenty accurate
  // at hiking scale (< a few km per segment).
  const mPerDegLat = 111320.0;
  final cosLat = cos(position.latitude * pi / 180);
  double toX(LatLng p) =>
      (p.longitude - position.longitude) * mPerDegLat * cosLat;
  double toY(LatLng p) => (p.latitude - position.latitude) * mPerDegLat;

  var best = double.infinity;
  for (var i = 1; i < points.length; i++) {
    final ax = toX(points[i - 1].latLng);
    final ay = toY(points[i - 1].latLng);
    final bx = toX(points[i].latLng);
    final by = toY(points[i].latLng);
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    // Projection of position onto segment ab, clamped to [0,1].
    final t = len2 > 0 ? ((-ax) * dx + (-ay) * dy) / len2 : 0.0;
    final tc = t.clamp(0.0, 1.0);
    final px = ax + tc * dx;
    final py = ay + tc * dy;
    final d = sqrt(px * px + py * py);
    if (d < best) best = d;
  }
  return best;
}

/// Index of the route point nearest to [position].
int nearestPointIndex(List<RoutePoint> points, LatLng position) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final d = metersBetween(points[i].latLng, position);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// Ramer–Douglas–Peucker simplification for geographic polylines.
/// Endpoints are always kept; interior points within [toleranceMeters]
/// (perpendicular distance) of the simplified line are dropped. Used
/// to bound track-log size — GPS tracks accumulate thousands of near-
/// redundant points that would otherwise bloat local storage and the
/// Firestore document (1 MB limit per trip).
List<T> simplifyPolyline<T>(
  List<T> items,
  double toleranceMeters,
  LatLng Function(T) toLatLng,
) {
  if (items.length <= 2) return items;
  final keep = List<bool>.filled(items.length, false);
  keep[0] = keep[items.length - 1] = true;

  // Iterative DP with an explicit stack of (start, end) index pairs.
  final stack = <(int, int)>[(0, items.length - 1)];
  while (stack.isNotEmpty) {
    final (lo, hi) = stack.removeLast();
    if (hi - lo < 2) continue;
    final a = toLatLng(items[lo]);
    final b = toLatLng(items[hi]);
    // Local flat projection around the segment — accurate at hiking
    // scale (segments here are far below 100 km).
    const mPerDegLat = 111320.0;
    final cosLat = cos(a.latitude * pi / 180);
    final ax = a.longitude * mPerDegLat * cosLat;
    final ay = a.latitude * mPerDegLat;
    final bx = b.longitude * mPerDegLat * cosLat;
    final by = b.latitude * mPerDegLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;

    var maxDist = -1.0;
    var maxIdx = -1;
    for (var i = lo + 1; i < hi; i++) {
      final p = toLatLng(items[i]);
      final px = p.longitude * mPerDegLat * cosLat;
      final py = p.latitude * mPerDegLat;
      double d;
      if (len2 <= 0) {
        d = sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
      } else {
        final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
        final qx = ax + t * dx, qy = ay + t * dy;
        d = sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
      }
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }
    if (maxDist > toleranceMeters && maxIdx > 0) {
      keep[maxIdx] = true;
      stack.add((lo, maxIdx));
      stack.add((maxIdx, hi));
    }
  }
  return [
    for (var i = 0; i < items.length; i++)
      if (keep[i]) items[i],
  ];
}
