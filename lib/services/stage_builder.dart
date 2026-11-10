import '../core/geo.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';

/// Rebuilds the day-by-day stage split from route geometry and trip
/// length. Deterministic: same route + same day count = same stages,
/// so stages never need to be stored in the cloud snapshot — they are
/// always derived data.
abstract final class StageBuilder {
  /// Recomputes [trip.stages] from its route. No-op without a route.
  static void recompute(Trip trip) {
    final route = trip.route;
    if (route == null || !route.hasRoute) return;
    final days = trip.hikingDays.clamp(1, 14);
    List<List<RoutePoint>> splits;
    // If overnight waypoints are placed (one fewer than days), split at
    // them so each stage ends where the user plans to sleep.
    final overnights = route.waypoints
        .where((w) => w.type == WaypointType.overnight)
        .toList();
    if (overnights.length == days - 1) {
      final bounds =
          overnights
              .map((w) => nearestPointIndex(route.points, w.latLng))
              .toList()
            ..sort();
      splits = splitAtIndices(route.points, bounds);
      if (splits.length != days) {
        splits = splitIntoStages(route.points, days);
      }
    } else {
      splits = splitIntoStages(route.points, days);
    }
    final stages = <Stage>[];
    for (var i = 0; i < splits.length; i++) {
      final pts = splits[i];
      final dist = routeDistanceMeters(pts);
      final stats = elevationStats(pts);
      final stage = Stage(
        id: '${trip.id}-s$i',
        number: i + 1,
        date: trip.startDate?.add(Duration(days: i)),
        points: pts,
        distanceMeters: dist,
        ascent: stats.ascent,
        descent: stats.descent,
        highestPoint: stats.highest,
        estimatedMinutes: estimateHikingMinutes(
          dist,
          stats.ascent,
          stats.descent,
          trip.pace,
          activity: trip.activity,
          withChildren: trip.children > 0,
        ),
        startName: i == 0
            ? (route.waypoints.isNotEmpty
                  ? route.waypoints.first.name
                  : 'Start')
            : 'Overnatting $i',
        endName: i == splits.length - 1
            ? (route.waypoints.length >= 2 ? route.waypoints.last.name : 'Mål')
            : 'Overnatting ${i + 1}',
      );
      stage.difficulty = analyzeStageDifficulty(stage);
      stage.challenges = stage.difficulty!.factors;
      stages.add(stage);
    }
    trip.stages = stages;
    // Route totals are derived from the same points as the stages, so
    // the summary card and the stage list can never disagree.
    final total = elevationStats(route.points);
    route.totalAscent = total.ascent;
    route.totalDescent = total.descent;
    route.highestPoint = total.highest;
    route.maxSlopeDegrees = steepestGradeDegrees(route.points);
  }
}
