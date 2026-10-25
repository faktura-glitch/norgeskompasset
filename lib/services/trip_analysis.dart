import '../models/stage.dart';
import '../models/trip.dart';
import '../models/weather.dart';

/// Aggregated weather conditions for a time window over a set of snapshots.
class ConditionsSummary {
  final double? minTemp;
  final double? maxTemp;
  final double? maxWind;
  final double? maxGust;
  final double totalPrecipMm;
  final int hoursWithData;
  final bool freezingTemps;
  final bool rainExpected;
  final bool strongWind;
  final bool limitedVisibility;

  const ConditionsSummary({
    this.minTemp,
    this.maxTemp,
    this.maxWind,
    this.maxGust,
    this.totalPrecipMm = 0,
    this.hoursWithData = 0,
    this.freezingTemps = false,
    this.rainExpected = false,
    this.strongWind = false,
    this.limitedVisibility = false,
  });

  bool get hasData => hoursWithData > 0;
}

class TripAnalysis {
  static const forecastMaxAge = Duration(hours: 12);

  static bool forecastIsFresh(WeatherSnapshot snapshot, DateTime now) {
    final age = now.difference(snapshot.retrievedAt);
    return age >= const Duration(minutes: -1) && age <= forecastMaxAge;
  }

  /// Weather snapshot stored under [stageKey] within a trip's weather map.
  static WeatherSnapshot? snapshotFor(Trip trip, String key) =>
      trip.weather[key];

  /// Summarizes forecast hours in [from, to) across given snapshots.
  /// Hours from multiple snapshot locations are merged (averaged per hour).
  static ConditionsSummary summarize(
      Iterable<WeatherSnapshot> snapshots, DateTime from, DateTime to) {
    final byHour = <int, List<WeatherHour>>{};
    for (final s in snapshots) {
      for (final h in s.hoursBetween(from, to)) {
        final key = h.time.millisecondsSinceEpoch ~/ 3600000;
        byHour.putIfAbsent(key, () => []).add(h);
      }
    }
    if (byHour.isEmpty) return const ConditionsSummary();

    double? minT, maxT, maxW, maxG;
    var precip = 0.0;
    var lowVis = false;
    for (final entry in byHour.entries) {
      final hs = entry.value;
      double? avg(List<double?> v) {
        final vals = v.whereType<double>();
        return vals.isEmpty
            ? null
            : vals.reduce((a, b) => a + b) / vals.length;
      }

      final t = avg(hs.map((h) => h.temperature).toList());
      final w = hs
          .map((h) => h.windSpeed)
          .whereType<double>()
          .fold<double?>(null, (a, b) => a == null || b > a ? b : a);
      final g = hs
          .map((h) => h.windGust)
          .whereType<double>()
          .fold<double?>(null, (a, b) => a == null || b > a ? b : a);
      final p = avg(hs.map((h) => h.precipitationMm).toList());
      final c = avg(hs.map((h) => h.cloudCover).toList());
      if (t != null) {
        if (minT == null || t < minT) minT = t;
        if (maxT == null || t > maxT) maxT = t;
      }
      if (w != null && (maxW == null || w > maxW)) maxW = w;
      if (g != null && (maxG == null || g > maxG)) maxG = g;
      if (p != null) precip += p;
      if (c != null && c > 95 && p != null && p > 0) lowVis = true;
    }
    return ConditionsSummary(
      minTemp: minT,
      maxTemp: maxT,
      maxWind: maxW,
      maxGust: maxG,
      totalPrecipMm: precip,
      hoursWithData: byHour.length,
      freezingTemps: minT != null && minT <= 0,
      rainExpected: precip >= 1.0,
      strongWind: (maxW ?? 0) >= 10.8 || (maxG ?? 0) >= 15,
      limitedVisibility: lowVis,
    );
  }

  /// Snapshots relevant for a stage — all sampled points along the
  /// stage (keys 'stageId-0..n'), plus the legacy single-key entry,
  /// else the whole-route snapshot as fallback.
  static List<WeatherSnapshot> snapshotsForStage(Trip trip, Stage stage) {
    final out = <WeatherSnapshot>[];
    final own = trip.weather[stage.id];
    if (own != null) out.add(own);
    for (final key in trip.weather.keys) {
      if (key.startsWith('${stage.id}-')) {
        final s = trip.weather[key];
        if (s != null) out.add(s);
      }
    }
    final route = trip.weather['route'];
    if (route != null && out.isEmpty) out.add(route);
    return out;
  }

  /// Day window for a stage: its date 06:00 → next day 06:00,
  /// or now→+24h when no date is set.
  static (DateTime, DateTime) stageWindow(Stage stage, Trip trip) {
    if (stage.date != null) {
      final d = stage.date!;
      final from = DateTime(d.year, d.month, d.day, 6);
      return (from, from.add(const Duration(days: 1)));
    }
    final base = trip.startDate ?? DateTime.now();
    final d = DateTime(base.year, base.month, base.day, 6)
        .add(Duration(days: stage.number - 1));
    return (d, d.add(const Duration(days: 1)));
  }

  /// Night window (overnight cold check): stage date 21:00 → +9h.
  static (DateTime, DateTime) nightWindow(Stage stage, Trip trip) {
    final (from, _) = stageWindow(stage, trip);
    final night = DateTime(from.year, from.month, from.day, 21);
    return (night, night.add(const Duration(hours: 9)));
  }

  /// Whether a date is beyond a forecast snapshot's coverage.
  static bool beyondForecast(WeatherSnapshot s, DateTime date) {
    final horizon = s.forecastHorizon;
    return horizon == null || date.isAfter(horizon);
  }
}
