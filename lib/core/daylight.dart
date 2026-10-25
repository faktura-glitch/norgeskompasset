import 'dart:math';

/// NOAA-style sunrise/sunset approximation for [date] at ([lat],
/// [lon]). Accurate to roughly ±5 minutes outside polar regions.
/// Returns null during polar night (sun never rises) or midnight sun
/// (sun never sets). Times are in local device time.
(DateTime? sunrise, DateTime? sunset) sunTimes(
  DateTime date,
  double lat,
  double lon,
) {
  const zenith = 90.833; // official zenith, incl. refraction
  final doy = date.difference(DateTime(date.year)).inDays + 1;
  final lngHour = lon / 15.0;

  double? utcHour(bool rising) {
    final t = doy + ((rising ? 6 : 18) - lngHour) / 24;
    final m = 0.9856 * t - 3.289;
    final l =
        (m +
            1.916 * sin(m * pi / 180) +
            0.020 * sin(2 * m * pi / 180) +
            282.634) %
        360;
    var ra = atan(0.91764 * tan(l * pi / 180)) * 180 / pi % 360;
    ra += (l ~/ 90 - ra ~/ 90) * 90;
    ra /= 15;
    final sinDec = 0.39782 * sin(l * pi / 180);
    final cosDec = cos(asin(sinDec));
    final cosH =
        (cos(zenith * pi / 180) - sinDec * sin(lat * pi / 180)) /
        (cosDec * cos(lat * pi / 180));
    if (cosH > 1 || cosH < -1) return null;
    final h =
        (rising ? 360 - acos(cosH) * 180 / pi : acos(cosH) * 180 / pi) /
        15;
    final tt = h + ra - 0.06571 * t - 6.622;
    return (tt - lngHour) % 24;
  }

  DateTime? at(bool rising) {
    final h = utcHour(rising);
    if (h == null) return null;
    final utc = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).add(Duration(milliseconds: (h * 3600000).round()));
    return utc.toLocal();
  }

  return (at(true), at(false));
}

/// Sunset for [date] at ([lat], [lon]), or null during polar night /
/// midnight sun.
DateTime? sunsetAt(DateTime date, double lat, double lon) =>
    sunTimes(date, lat, lon).$2;
