import '../core/geo.dart';
import '../models/gear.dart';
import '../models/planning_context.dart';
import '../models/profile.dart';
import '../models/route_models.dart';
import '../models/trip.dart';
import '../models/weather.dart';
import 'packing_engine.dart';
import 'trip_analysis.dart';

/// True when any day of the trip falls inside the yearly period
/// [startMonth]/[startDay]–[endMonth]/[endDay] (inclusive). Trips
/// without dates return false — a rule is never asserted on a guess.
bool tripOverlapsPeriod(
  Trip trip, {
  required int startMonth,
  required int startDay,
  required int endMonth,
  required int endDay,
}) {
  final start = trip.startDate;
  if (start == null) return false;
  final end = trip.endDate ?? start;
  for (final year in {start.year, end.year}) {
    final from = DateTime(year, startMonth, startDay);
    final to = DateTime(year, endMonth, endDay, 23, 59);
    if (!end.isBefore(from) && !start.isAfter(to)) return true;
  }
  return false;
}

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
      coverage = elevationCoverage(route.points);
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
      bool covers(
        Iterable<WeatherSnapshot> candidates,
        DateTime from,
        DateTime to,
      ) => candidates.any((s) {
        final hours = s.hoursBetween(from, to);
        return hours.isNotEmpty &&
            !hours.first.time.isAfter(from.add(const Duration(hours: 6))) &&
            !hours.last.time.isBefore(to.subtract(const Duration(hours: 6)));
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
          DateTime(
            end.year,
            end.month,
            end.day,
            6,
          ).add(const Duration(days: 1)),
        );
      }
      // A forecast that ends before the trip even starts is not a gap in
      // the data — MET only looks ~9 days ahead. Say so instead of
      // "doesn't cover the trip", which reads like an error.
      final start = trip.startDate;
      final beyondHorizon =
          start != null &&
          snapshots.every(
            (s) =>
                s.hours.isEmpty ||
                s.hours.last.time.isBefore(
                  DateTime(start.year, start.month, start.day, 6),
                ),
          );
      weatherQuality = stale
          ? DataQuality.stale
          : coversDates
          ? DataQuality.good
          : beyondHorizon
          ? DataQuality.beyondHorizon
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
    // Norwegian seasonal rules that depend only on the dates.
    if (cond.overnight &&
        tripOverlapsPeriod(
          trip,
          startMonth: 4,
          startDay: 15,
          endMonth: 9,
          endDay: 15,
        )) {
      checks.add(
        'Generelt bålforbud 15. april–15. september: ikke bål i eller nær '
        'skog og utmark. Bruk brenner – og sjekk kommunens regler, noen '
        'har totalforbud i tørre perioder.',
      );
    }
    if (cond.withDog &&
        tripOverlapsPeriod(
          trip,
          startMonth: 4,
          startDay: 1,
          endMonth: 8,
          endDay: 20,
        )) {
      checks.add(
        'Båndtvang 1. april–20. august: hunden skal gå i bånd. Mange '
        'kommuner har utvidet båndtvang i beiteområder – sjekk lokalt.',
      );
    }
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
          'Varselet dekker bare de første dagene av turen – hent det igjen '
          'nærmere avreise for resten.',
        );
      case DataQuality.beyondHorizon:
        checks.add(
          'Værvarselet går bare ca. 9 dager frem og rekker ikke til turen '
          'ennå. Listen bygger på sesongen – hent været igjen nærmere '
          'avreise.',
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
