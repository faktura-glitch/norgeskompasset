import '../core/format.dart';
import '../core/geo.dart';
import '../models/gear.dart';
import '../models/trip.dart';
import 'trip_analysis.dart';
import 'what_if.dart';

/// The five areas «Turklarhet» looks at. Each maps to one screen the
/// user can jump to.
enum ReadinessArea { route, gear, weather, food, safety }

extension ReadinessAreaX on ReadinessArea {
  String get label => switch (this) {
    ReadinessArea.route => 'Rute',
    ReadinessArea.gear => 'Utstyr',
    ReadinessArea.weather => 'Vær',
    ReadinessArea.food => 'Mat og vann',
    ReadinessArea.safety => 'Sikkerhet',
  };
}

/// `check` is something the user should look at; `missing` is a hole
/// in the plan.
enum ReadinessLevel { ok, check, missing }

class ReadinessIssue {
  final ReadinessArea area;
  final ReadinessLevel level;
  final String text;

  const ReadinessIssue(this.area, this.level, this.text);
}

/// Answers «er jeg klar for denne turen?» from data the app already
/// has. It never invents data: an unfetched forecast is reported as
/// unfetched, not as good weather.
class TripReadiness {
  final List<ReadinessIssue> issues;

  const TripReadiness(this.issues);

  ReadinessLevel levelFor(ReadinessArea area) => issues
      .where((i) => i.area == area)
      .fold(ReadinessLevel.ok, (l, i) => i.level.index > l.index ? i.level : l);

  /// 0–100: every area without remarks counts fully, an area with
  /// only things to check counts half, a hole counts nothing.
  int get percent {
    var score = 0.0;
    for (final a in ReadinessArea.values) {
      score += switch (levelFor(a)) {
        ReadinessLevel.ok => 1,
        ReadinessLevel.check => 0.5,
        ReadinessLevel.missing => 0,
      };
    }
    return (score / ReadinessArea.values.length * 100).round();
  }

  bool get ready => issues.isEmpty;

  String get headline => ready
      ? 'Turklar – alt henger sammen'
      : 'Turklarhet $percent % – ${fmtCount(issues.length, 'ting', 'ting')} bør avklares';

  static TripReadiness evaluate(Trip trip, TripConditions cond) {
    final issues = <ReadinessIssue>[];
    void add(ReadinessArea a, ReadinessLevel l, String t) =>
        issues.add(ReadinessIssue(a, l, t));

    // ── Rute ───────────────────────────────────────────────
    final route = trip.route;
    final hasRoute =
        route != null && route.hasRoute && route.distanceMeters > 0;
    if (!hasRoute) {
      add(ReadinessArea.route, ReadinessLevel.missing, 'Ruten er ikke tegnet.');
    }
    if (trip.startDate == null) {
      add(
        ReadinessArea.route,
        ReadinessLevel.missing,
        'Dato mangler – trengs for værvarsel og sesong.',
      );
    }
    if (trip.accommodation == AccommodationType.dayHike &&
        trip.hikingDays > 1) {
      add(
        ReadinessArea.route,
        ReadinessLevel.check,
        'Dagstur over ${fmtCount(trip.hikingDays, 'dag', 'dager')} – velg '
        'overnatting i Turoppsett, eller sett turen til én dag.',
      );
    }
    final est = trip.totalEstimatedMinutes;
    final recommended = recommendedTripDays(
      est,
      withChildren: trip.children > 0,
    );
    if (hasRoute && recommended > trip.hikingDays) {
      add(
        ReadinessArea.route,
        ReadinessLevel.check,
        'Anslått ${fmtDuration(est)} er langt for '
        '${fmtCount(trip.hikingDays, 'dag', 'dager')} – anbefalt '
        '${fmtCount(recommended, 'dag', 'dager')}.',
      );
    }

    // ── Utstyr ─────────────────────────────────────────────
    final items = trip.packingList;
    if (items.isEmpty) {
      add(
        ReadinessArea.gear,
        ReadinessLevel.missing,
        'Pakkelisten er ikke laget.',
      );
    } else if (trip.missingRequiredCount > 0) {
      add(
        ReadinessArea.gear,
        ReadinessLevel.check,
        '${fmtCount(trip.missingRequiredCount, 'nødvendig ting', 'nødvendige ting')} '
        'er ikke pakket.',
      );
    }

    // ── Vær ────────────────────────────────────────────────
    if (trip.startDate != null) {
      final snapshots = trip.weather.values.toList();
      if (snapshots.isEmpty) {
        add(
          ReadinessArea.weather,
          ReadinessLevel.check,
          'Værvarsel er ikke hentet.',
        );
      } else {
        final now = DateTime.now();
        final fresh = snapshots.any(
          (s) => TripAnalysis.forecastIsFresh(s, now),
        );
        if (!fresh) {
          final newest = snapshots
              .map((s) => s.retrievedAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          final age = now.difference(newest);
          add(
            ReadinessArea.weather,
            ReadinessLevel.check,
            'Værvarselet er ${age.inHours < 48 ? '${age.inHours} t' : fmtCount(age.inDays, 'dag', 'dager')} '
            'gammelt – hent på nytt.',
          );
        }
      }
      if (trip.alerts.isNotEmpty) {
        add(
          ReadinessArea.weather,
          ReadinessLevel.check,
          '${fmtCount(trip.alerts.length, 'farevarsel', 'farevarsler')} fra MET '
          'gjelder området – les dem.',
        );
      }
    }

    // ── Mat og vann ────────────────────────────────────────
    final plan = trip.mealPlan;
    final overnight = trip.accommodation != AccommodationType.dayHike;
    if (plan == null) {
      if (overnight) {
        add(
          ReadinessArea.food,
          ReadinessLevel.missing,
          'Matplanen er ikke laget.',
        );
      }
    } else if (plan.days != trip.hikingDays) {
      add(
        ReadinessArea.food,
        ReadinessLevel.check,
        'Matplanen gjelder ${fmtCount(plan.days, 'dag', 'dager')}, turen er '
        '${fmtCount(trip.hikingDays, 'dag', 'dager')} – lag den på nytt.',
      );
    }
    if (items.isNotEmpty) {
      if (checkNeed(items, TripNeed.water).state == NeedState.missing) {
        add(
          ReadinessArea.food,
          ReadinessLevel.missing,
          'Ingen vannløsning på listen (flaske, filter eller termos).',
        );
      } else if (plan != null && plan.totalWaterWeightGrams == 0) {
        add(
          ReadinessArea.food,
          ReadinessLevel.check,
          'Vann fylles underveis – sjekk at det er vann langs ruten.',
        );
      }
    }

    // ── Sikkerhet ──────────────────────────────────────────
    if (trip.lastSharedAt == null && trip.expectedReturn == null) {
      add(
        ReadinessArea.safety,
        ReadinessLevel.check,
        'Turplanen er ikke sendt til noen, og hjemkomst er ikke satt.',
      );
    } else if (trip.expectedReturn == null) {
      add(
        ReadinessArea.safety,
        ReadinessLevel.check,
        'Forventet hjemkomst er ikke satt.',
      );
    }
    if (items.isNotEmpty) {
      if (checkNeed(items, TripNeed.firstAid).state == NeedState.missing) {
        add(
          ReadinessArea.safety,
          ReadinessLevel.missing,
          'Førstehjelp mangler på listen.',
        );
      }
      if (navigationCheck(items).state == NeedState.missing) {
        add(
          ReadinessArea.safety,
          ReadinessLevel.missing,
          'Ingen navigasjon utenom mobilen (kart og kompass).',
        );
      }
      final gaps = whatIfChecks(
        trip,
        cond,
      ).where((w) => w.state == NeedState.missing).length;
      if (gaps > 0) {
        add(
          ReadinessArea.safety,
          ReadinessLevel.check,
          '«Hva hvis?»: ${fmtCount(gaps, 'situasjon', 'situasjoner')} er ikke dekket.',
        );
      }
    }

    return TripReadiness(issues);
  }
}
