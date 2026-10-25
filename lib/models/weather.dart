/// One hourly forecast step, parsed from MET Norway Locationforecast.
class WeatherHour {
  final DateTime time; // UTC
  final double? temperature;
  final double? precipitationMm; // next-hour precipitation when available
  final double? windSpeed; // m/s
  final double? windGust; // m/s
  final double? cloudCover; // percent
  final String? symbolCode;

  const WeatherHour({
    required this.time,
    this.temperature,
    this.precipitationMm,
    this.windSpeed,
    this.windGust,
    this.cloudCover,
    this.symbolCode,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'temp': temperature,
        'precip': precipitationMm,
        'wind': windSpeed,
        'gust': windGust,
        'cloud': cloudCover,
        'symbol': symbolCode,
      };

  factory WeatherHour.fromJson(Map<String, dynamic> j) => WeatherHour(
        time: DateTime.parse(j['time'] as String),
        temperature: (j['temp'] as num?)?.toDouble(),
        precipitationMm: (j['precip'] as num?)?.toDouble(),
        windSpeed: (j['wind'] as num?)?.toDouble(),
        windGust: (j['gust'] as num?)?.toDouble(),
        cloudCover: (j['cloud'] as num?)?.toDouble(),
        symbolCode: j['symbol'] as String?,
      );
}

/// A forecast for a single location on/near the route.
class WeatherSnapshot {
  final double lat;
  final double lon;
  final double? elevation;
  final DateTime retrievedAt;

  /// MET 'updated_at' — when the forecast model data was issued.
  final DateTime? forecastIssuedAt;
  final List<WeatherHour> hours;
  final String source;

  const WeatherSnapshot({
    required this.lat,
    required this.lon,
    this.elevation,
    required this.retrievedAt,
    this.forecastIssuedAt,
    this.hours = const [],
    this.source = 'MET Norway Locationforecast 2.0',
  });

  /// Hours between [from] inclusive and [to] exclusive.
  List<WeatherHour> hoursBetween(DateTime from, DateTime to) => hours
      .where((h) => !h.time.isBefore(from) && h.time.isBefore(to))
      .toList();

  /// Latest hour covered by this forecast.
  DateTime? get forecastHorizon =>
      hours.isEmpty ? null : hours.last.time;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'ele': elevation,
        'retrievedAt': retrievedAt.toIso8601String(),
        'issuedAt': forecastIssuedAt?.toIso8601String(),
        'source': source,
        'hours': hours.map((h) => h.toJson()).toList(),
      };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> j) => WeatherSnapshot(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        elevation: (j['ele'] as num?)?.toDouble(),
        retrievedAt: DateTime.parse(j['retrievedAt'] as String),
        forecastIssuedAt: j['issuedAt'] != null
            ? DateTime.tryParse(j['issuedAt'] as String)
            : null,
        source: j['source'] as String? ?? 'MET Norway',
        hours: (j['hours'] as List? ?? [])
            .map((h) => WeatherHour.fromJson(Map<String, dynamic>.from(h)))
            .toList(),
      );
}
