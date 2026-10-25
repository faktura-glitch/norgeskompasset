import 'package:intl/intl.dart';

final _dayFmt = DateFormat('d. MMM yyyy', 'nb_NO');
final _dayTimeFmt = DateFormat('d. MMM HH:mm', 'nb_NO');
final _timeFmt = DateFormat('HH:mm');
final _weekdayFmt = DateFormat('EEEE d. MMM', 'nb_NO');

String fmtDate(DateTime? d) => d == null ? '–' : _dayFmt.format(d);
String fmtDateTime(DateTime? d) => d == null ? '–' : _dayTimeFmt.format(d);
String fmtTime(DateTime? d) => d == null ? '–' : _timeFmt.format(d);
String fmtWeekday(DateTime? d) => d == null ? '–' : _weekdayFmt.format(d);

/// Count with the right Norwegian singular/plural form: '1 dag', '3 dager'.
String fmtCount(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String fmtKm(double meters) {
  if (meters >= 10000) return '${(meters / 1000).toStringAsFixed(0)} km';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String fmtMeters(double? m) => m == null ? '–' : '${m.round()} moh';

String fmtDuration(double minutes) {
  if (minutes <= 0) return '–';
  final h = minutes ~/ 60;
  final m = (minutes % 60).round();
  if (h == 0) return '$m min';
  if (m == 0) return '$h t';
  return '$h t $m min';
}

String fmtWeight(double grams) {
  if (grams >= 1000) {
    final kg = grams / 1000;
    return '${kg.toStringAsFixed(kg >= 10 ? 0 : 1)} kg';
  }
  return '${grams.round()} g';
}

String fmtWind(double? ms) => ms == null ? '–' : '${ms.toStringAsFixed(0)} m/s';
String fmtTemp(double? c) => c == null ? '–' : '${c.toStringAsFixed(0)}°';
String fmtPrecip(double? mm) =>
    mm == null ? '–' : '${mm.toStringAsFixed(1)} mm';

/// Relative freshness label, e.g. 'hentet for 12 min siden'.
String fmtAge(DateTime? t) {
  if (t == null) return 'aldri';
  final age = DateTime.now().difference(t);
  if (age.inMinutes < 1) return 'hentet nå';
  if (age.inMinutes < 60) return 'hentet for ${age.inMinutes} min siden';
  if (age.inHours < 24) return 'hentet for ${age.inHours} t siden';
  return 'hentet for ${age.inDays} d siden';
}
