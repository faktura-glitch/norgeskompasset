import '../core/daylight.dart';
import '../core/format.dart';
import '../models/stage.dart';
import '../models/trip.dart';
import 'trip_analysis.dart';

enum AssessmentLevel { easy, planning, demanding }

extension AssessmentLevelX on AssessmentLevel {
  String get label => switch (this) {
    AssessmentLevel.easy => 'Grei tur',
    AssessmentLevel.planning => 'Krever god planlegging',
    AssessmentLevel.demanding => 'Krevende – vurder oppdeling eller alternativ',
  };
}

/// «Er denne turen riktig for meg?» answered from the trip's own
/// facts: distance, ascent, stage difficulty, daylight, forecast and
/// who is coming. It never judges the user's ability.
class TripAssessment {
  final AssessmentLevel level;

  /// Short reasons, most important first.
  final List<String> points;

  /// What the assessment could not take into account.
  final List<String> caveats;

  const TripAssessment(this.level, this.points, this.caveats);

  static TripAssessment? forTrip(Trip trip) {
    final route = trip.route;
    if (route == null || !route.hasRoute || route.distanceMeters <= 0) {
      return null;
    }
    final points = <String>[];
    final caveats = <String>[];
    var score = 0;
    void add(int weight, String text) {
      score += weight;
      points.add(text);
    }

    final days = trip.hikingDays.clamp(1, 60);
    final kmPerDay = route.distanceMeters / 1000 / days;
    if (kmPerDay >= 20) {
      add(
        2,
        'Lang distanse: ${fmtKm(route.distanceMeters)}'
        '${days > 1 ? ' – rundt ${kmPerDay.round()} km per dag' : ''}.',
      );
    } else if (kmPerDay >= 12) {
      add(
        1,
        'God distanse: ${fmtKm(route.distanceMeters)}'
        '${days > 1 ? ' – rundt ${kmPerDay.round()} km per dag' : ''}.',
      );
    }

    final hasElevation = route.points.any((p) => p.elevation != null);
    if (hasElevation) {
      final ascentPerDay = route.totalAscent / days;
      if (ascentPerDay >= 1000) {
        add(
          2,
          'Stor stigning: +${route.totalAscent.round()} m'
          '${days > 1 ? ' fordelt på $days dager' : ''}.',
        );
      } else if (ascentPerDay >= 500) {
        add(1, 'Betydelig stigning: +${route.totalAscent.round()} m.');
      }
    } else {
      caveats.add('Høydedata er ikke hentet – stigning er ikke vurdert.');
    }

    Stage? hardest;
    for (final s in trip.stages) {
      if (hardest == null ||
          (s.difficulty?.score ?? 0) > (hardest.difficulty?.score ?? 0)) {
        hardest = s;
      }
    }
    final level = hardest?.difficulty?.level;
    if (level == DifficultyLevel.demanding) {
      add(2, 'Etappe ${hardest!.number} er svært krevende.');
    } else if (level == DifficultyLevel.challenging) {
      add(1, 'Etappe ${hardest!.number} er krevende.');
    }

    // Daylight on the longest day, measured at the route start.
    if (trip.startDate != null && trip.stages.isNotEmpty) {
      final longest = trip.stages.reduce(
        (a, b) => a.estimatedMinutes >= b.estimatedMinutes ? a : b,
      );
      final date = longest.date ?? trip.startDate!;
      final start = route.points.first;
      final (rise, set) = sunTimes(date, start.lat, start.lon);
      if (rise != null && set != null) {
        final daylight = set.difference(rise).inMinutes.toDouble();
        if (longest.estimatedMinutes > daylight * 0.8) {
          add(
            2,
            'Lite dagslys: ${fmtDuration(daylight)} lyst ${fmtDate(date)}, '
            'etappe ${longest.number} er anslått til '
            '${fmtDuration(longest.estimatedMinutes)}. Start tidlig og ta '
            'med hodelykt.',
          );
        } else if (longest.estimatedMinutes > daylight * 0.6) {
          add(
            1,
            'Dagslyset holder, men med liten margin: ${fmtDuration(daylight)} '
            'lyst mot ${fmtDuration(longest.estimatedMinutes)} anslått for '
            'etappe ${longest.number}.',
          );
        }
      }
    } else {
      caveats.add('Uten dato og etapper er dagslys ikke vurdert.');
    }

    // Forecast for the trip window, when fetched.
    if (trip.startDate != null && trip.weather.isNotEmpty) {
      final from = trip.startDate!;
      final to = (trip.endDate ?? from).add(const Duration(days: 1));
      final w = TripAnalysis.summarize(trip.weather.values, from, to);
      if (w.hasData) {
        if (w.strongWind) {
          add(
            1,
            'Sterk vind er meldt (inntil ${w.maxGust?.round() ?? w.maxWind?.round()} m/s i kast).',
          );
        }
        if (w.freezingTemps && trip.season != TripSeason.winter) {
          add(1, 'Kuldegrader er meldt (ned mot ${fmtTemp(w.minTemp)}).');
        }
        if (w.rainExpected && w.totalPrecipMm >= 10) {
          add(
            1,
            'Mye nedbør er meldt (${w.totalPrecipMm.round()} mm) – '
            'vått underlag tar lengre tid.',
          );
        }
        if (w.limitedVisibility) {
          add(1, 'Dårlig sikt er mulig – navigasjon blir mer krevende.');
        }
      } else {
        caveats.add('Værvarselet dekker ikke turdatoene ennå.');
      }
    } else {
      caveats.add(
        'Værvarsel er ikke hentet – vurder på nytt når det er klart.',
      );
    }

    if (trip.avalancheTerrain == true) {
      add(
        2,
        'Ruten går i skredterreng – krever skredkunnskap og sjekk av '
        'varsom.no.',
      );
    }
    if (trip.children > 0 && (kmPerDay >= 10 || score >= 2)) {
      add(1, 'Med barn: regn med lavere tempo og flere pauser.');
    }

    final result = score <= 1
        ? AssessmentLevel.easy
        : score <= 3
        ? AssessmentLevel.planning
        : AssessmentLevel.demanding;
    if (points.isEmpty) {
      points.add('Moderat distanse og stigning – en overkommelig tur.');
    }
    return TripAssessment(result, points, caveats);
  }
}
