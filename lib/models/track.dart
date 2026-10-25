/// A recorded GPS position captured during active hiking mode.
/// Timestamps make the log exportable as a real GPX track.
class TrackPoint {
  final double lat;
  final double lon;
  final double? elevation;
  final DateTime time;

  const TrackPoint(this.lat, this.lon, this.elevation, this.time);

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'ele': elevation,
        'time': time.toIso8601String(),
      };

  factory TrackPoint.fromJson(Map<String, dynamic> j) => TrackPoint(
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
        (j['ele'] as num?)?.toDouble(),
        DateTime.tryParse(j['time']?.toString() ?? '') ??
            DateTime.now(),
      );
}
