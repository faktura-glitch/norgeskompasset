import '../models/stage.dart';
import '../models/trip.dart';
import 'geo.dart';

/// Daily energy estimate based on MET values (Metabolic Equivalent
/// of Task) — the standard way to price physical work: energy burn =
/// MET × 3.5 × body mass(kg) ÷ 200 × minutes.
///
/// The stage's steepness (ascent metres per hour of estimated hiking
/// time) picks the MET band, so a day with lots of climbing costs
/// more than a flat day of the same length:
///  - <150 m/h ascent (flat/easy):    5.0 MET
///  - 150–300 m/h (rolling):          6.5 MET
///  - 300–450 m/h (steep):            7.5 MET
///  - >450 m/h (very steep):          9.0 MET
/// A net-downhill day (>400 m more descent than ascent) subtracts
/// 1.5 MET — descending is cheaper than climbing. Pack weight adds
/// ~0.4 MET per 10 kg (capped at +1.2), and the chosen hiking pace
/// shifts ±0.5. All figures are planning estimates, not medical
/// advice — real needs vary with wind, snow, fitness and metabolism.
class EnergyEstimate {
  /// Total estimated need per person per day.
  final double kcalPerDay;

  /// Resting + camp-life metabolism: ~24 kcal per kg body weight.
  final double baseKcal;

  /// MET-priced cost of the moving hours.
  final double activityKcal;

  /// Cold supplement: ~20 kcal per °C below 8 °C (≤ 450 kcal).
  final double coldKcal;

  /// Minutes-weighted mean MET across stages — shown for transparency.
  final double avgMet;

  /// Average carried weight per person (pack weight / participants).
  final double packKg;
  final double bodyKg;

  /// True when a forecast temperature fed the cold supplement —
  /// false means the estimate is missing one input and runs low.
  final bool temperatureKnown;

  const EnergyEstimate({
    required this.kcalPerDay,
    required this.baseKcal,
    required this.activityKcal,
    required this.coldKcal,
    required this.avgMet,
    required this.packKg,
    required this.bodyKg,
    required this.temperatureKnown,
  });
}

/// MET band for one stage-like workload. [ascentM] per hiking hour
/// is the terrain signal; [descentM] > ascent marks a cheap
/// net-downhill day.
double _metFor({
  required double ascentM,
  required double descentM,
  required double minutes,
  required double packKg,
  required HikingPace pace,
}) {
  final hours = minutes / 60;
  final ascPerHour = hours > 0 ? ascentM / hours : 0.0;
  var met = ascPerHour < 150
      ? 5.0
      : ascPerHour < 300
      ? 6.5
      : ascPerHour < 450
      ? 7.5
      : 9.0;
  if (descentM > ascentM && descentM > 400) {
    met = (met - 1.5).clamp(4.0, 9.0);
  }
  met += (packKg / 10).clamp(0.0, 3.0) * 0.4;
  met += switch (pace) {
    HikingPace.relaxed => -0.5,
    HikingPace.normal => 0.0,
    HikingPace.brisk => 0.5,
  };
  return met.clamp(3.5, 10.0);
}

double _kcalFor(double met, double kg, double minutes) =>
    met * 3.5 * kg / 200 * minutes;

/// Estimates daily energy need for a typical stage day on [trip].
/// Averages across stages so one heavy day doesn't dominate.
/// [bodyKg] comes from the user profile (75 kg fallback);
/// [packKg] is the carried weight divided by participants. Worn
/// items are on the body and are not counted as pack load.
/// [minTempC] is the coldest forecast temperature if fetched.
EnergyEstimate estimateDailyKcal(
  Trip trip, {
  double bodyKg = 75,
  double? minTempC,
}) {
  final stages = trip.stages;
  final people = trip.participants.clamp(1, 20);
  final packKg =
      trip.packingList
          .where((i) => !i.worn)
          .fold(0.0, (s, i) => s + i.totalWeightGrams) /
      1000 /
      people;
  final totalKg = bodyKg + packKg;

  // One (dist, ascent, descent, minutes) workload per hiking day —
  // real stages when they exist, otherwise a synthetic split of the
  // route so a route-only trip still gets a MET estimate.
  final workloads = <({double asc, double desc, double min})>[];
  if (stages.isNotEmpty) {
    for (final Stage s in stages) {
      workloads.add((asc: s.ascent, desc: s.descent, min: s.estimatedMinutes));
    }
  } else if (trip.route?.hasRoute == true) {
    final r = trip.route!;
    final days = trip.hikingDays.clamp(1, 14);
    final dist = r.distanceMeters / days;
    final asc = r.totalAscent / days;
    final desc = r.totalDescent / days;
    workloads.add((
      asc: asc,
      desc: desc,
      min: estimateHikingMinutes(
        dist,
        asc,
        desc,
        trip.pace,
        activity: trip.activity,
        withChildren: trip.children > 0,
      ),
    ));
  }

  var activity = 0.0, metMin = 0.0, totalMin = 0.0;
  for (final w in workloads) {
    final met = _metFor(
      ascentM: w.asc,
      descentM: w.desc,
      minutes: w.min,
      packKg: packKg,
      pace: trip.pace,
    );
    activity += _kcalFor(met, totalKg, w.min);
    metMin += met * w.min;
    totalMin += w.min;
  }
  if (workloads.isNotEmpty) activity /= workloads.length;
  final avgMet = totalMin > 0 ? metMin / totalMin : 0.0;

  final base = bodyKg * 24;
  final cold = minTempC != null ? ((8 - minTempC).clamp(0.0, 22.5)) * 20 : 0.0;

  return EnergyEstimate(
    kcalPerDay: base + activity + cold,
    baseKcal: base,
    activityKcal: activity,
    coldKcal: cold,
    avgMet: avgMet,
    packKg: packKg,
    bodyKg: bodyKg,
    temperatureKnown: minTempC != null,
  );
}
