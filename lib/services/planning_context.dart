import '../models/gear.dart';
import '../models/planning_context.dart';
import '../models/profile.dart';
import '../models/route_models.dart';
import '../models/trip.dart';
import '../models/weather.dart';
import 'packing_engine.dart';
import 'trip_analysis.dart';

/// Builds [PlanningContext] — the single derived bridge between the
/// route/external conditions and the generated plans. Pure computation:
/// reads the trip, never mutates it, never fabricates missing data.
abstract final class PlanningContextBuilder {
  static PlanningContext forTrip(Trip trip, UserProfile profile) {
    final engine = PackingEngine();
    final cond = engine.conditionsFor(trip, profile);
    final route = trip.route;
    final hasRoute = route != null && route.hasRoute;

    // ── Route facts ────────────────────────────────────────
    double? coverage;
    if (hasRoute && route.points.isNotEmpty) {
      final withEle = route.points.where((p) => p.elevation != null).length;
      coverage = withEle / route.points.length;
    }
    final estimatedLegs =
        hasRoute &&
        (route.source == RouteSource.estimated ||
            route.source == RouteSource.mixed ||
            route.straightRanges.isNotEmpty);

    // ── Weather freshness & coverage ───────────────────────
    var weatherQuality = DataQuality.missing;
    final snapshots = trip.weather.values.toList();
    if (snapshots.isNotEmpty) {
      final stale = snapshots.any(
        (s) => !TripAnalysis.forecastIsFresh(s, DateTime.now()),
      );
      // A fresh point at the end of a trip does not cover the other
      // stages. Check the relevant window for every stage instead.
      bool covers(Iterable<WeatherSnapshot> candidates,
          DateTime from, DateTime to) =>
          candidates.any((s) {
            final hours = s.hoursBetween(from, to);
            return hours.isNotEmpty &&
                !hours.first.time.isAfter(from.add(const Duration(hours: 6))) &&
                !hours.last.time.isBefore(
                  to.subtract(const Duration(hours: 6)),
                );
          });
      bool coversDates;
      if (trip.stages.isNotEmpty) {
        coversDates = trip.stages.every((stage) {
          final (from, to) = TripAnalysis.stageWindow(stage, trip);
          return covers(TripAnalysis.snapshotsForStage(trip, stage), from, to);
        });
      } else if (trip.startDate == null) {
        coversDates = snapshots.any((s) => s.hours.isNotEmpty);
      } else {
        final start = trip.startDate!;
        final end = trip.endDate ?? start;
        coversDates = covers(
          snapshots,
          DateTime(start.year, start.month, start.day, 6),
          DateTime(end.year, end.month, end.day, 6)
              .add(const Duration(days: 1)),
        );
      }
      weatherQuality = stale
          ? DataQuality.stale
          : coversDates
          ? DataQuality.good
          : DataQuality.partial;
    }

    // ── Avalanche basis ────────────────────────────────────
    AvalancheBasis basis;
    int? maxDanger;
    if (trip.avalancheWarnings.isNotEmpty) {
      basis = AvalancheBasis.warning;
      for (final w in trip.avalancheWarnings) {
        if (maxDanger == null || w.dangerLevel > maxDanger) {
          maxDanger = w.dangerLevel;
        }
      }
    } else if (trip.avalancheTerrain == true) {
      basis = AvalancheBasis.userConfirmed;
    } else if (trip.avalancheTerrain == false) {
      basis = AvalancheBasis.userExcluded;
    } else if (cond.avalanche == AvalancheRisk.uncertain) {
      basis = AvalancheBasis.notAssessed;
    } else {
      basis = AvalancheBasis.notRelevant;
    }

    // ── Honest gaps the user must check ────────────────────
    final checks = <String>[];
    if (estimatedLegs) {
      checks.add(
        'Ruten inneholder estimerte strekk – linjen er ikke et '
        'kontrollert stispor.',
      );
    }
    if (hasRoute && coverage != null && coverage < 0.9) {
      checks.add(
        'Høydedata dekker bare ${(coverage * 100).round()} % av ruten – '
        'stigningstallene er usikre.',
      );
    }
    switch (weatherQuality) {
      case DataQuality.missing:
        checks.add('Ingen værprognose hentet – hent før avreise.');
      case DataQuality.stale:
        checks.add('Prognosen er hentet for over 12 timer siden – oppdater.');
      case DataQuality.partial:
        checks.add(
          'Værdata dekker ikke hele turen – hent på nytt eller sjekk Yr '
          'nærmere avreise.',
        );
      case DataQuality.good:
        break;
    }
    if (basis == AvalancheBasis.notAssessed) {
      checks.add(
        'Skredfare er ikke vurdert – sjekk varsom.no og terrenget på ruten.',
      );
    }

    return PlanningContext(
      activity: trip.activity,
      carry: trip.carry,
      accommodation: trip.accommodation,
      days: trip.hikingDays,
      participants: trip.participants,
      conditions: cond,
      distanceKm: hasRoute ? route.distanceMeters / 1000 : null,
      totalAscentM: hasRoute && (coverage ?? 0) > 0 ? route.totalAscent : null,
      routeSource: hasRoute ? route.source : null,
      hasEstimatedLegs: estimatedLegs,
      elevationCoverage: coverage,
      weatherQuality: weatherQuality,
      minTempC: cond.minTemp,
      avalancheBasis: basis,
      maxDangerLevel: maxDanger,
      userChecks: checks,
    );
  }
}
