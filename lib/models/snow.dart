/// Modelled snow conditions at one point along the route, from NVE's
/// seNorge grid (1 × 1 km). Values are daily and modelled, so local
/// depth in steep terrain can differ a lot.
class SnowSample {
  final int? stageNumber;
  final String name;
  final double lat;
  final double lon;

  /// Snow depth in cm on [date]; null when the grid has no data.
  final double? depthCm;

  /// New snow over the three days up to [date], in cm.
  final double? freshCm3d;
  final DateTime date;
  final double? altitude;
  final DateTime retrievedAt;

  const SnowSample({
    this.stageNumber,
    this.name = '',
    required this.lat,
    required this.lon,
    this.depthCm,
    this.freshCm3d,
    required this.date,
    this.altitude,
    required this.retrievedAt,
  });

  Map<String, dynamic> toJson() => {
    'stage': stageNumber,
    'name': name,
    'lat': lat,
    'lon': lon,
    'depth': depthCm,
    'fresh': freshCm3d,
    'date': date.toIso8601String(),
    'alt': altitude,
    'at': retrievedAt.toIso8601String(),
  };

  factory SnowSample.fromJson(Map<String, dynamic> j) => SnowSample(
    stageNumber: j['stage'] as int?,
    name: j['name'] as String? ?? '',
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lon: (j['lon'] as num?)?.toDouble() ?? 0,
    depthCm: (j['depth'] as num?)?.toDouble(),
    freshCm3d: (j['fresh'] as num?)?.toDouble(),
    date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
    altitude: (j['alt'] as num?)?.toDouble(),
    retrievedAt: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
  );
}
