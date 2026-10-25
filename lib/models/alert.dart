/// An official warning from MET Norway's metalerts API (CAP-based).
/// Covers meteorological and natural hazards for Norwegian areas.
class MetAlert {
  final String id;
  final String title;
  final String description;
  final String instruction;
  final String event; // e.g. 'rainFlood', 'wind', 'thunderstorm'
  final String severity; // 'Minor' | 'Moderate' | 'Severe' | 'Extreme'
  final int awarenessLevel; // 1-4 (green/yellow/orange/red)
  final String awarenessName; // 'Minor' | 'Moderate' | 'Severe' | 'Extreme'
  final String area;
  final DateTime? validFrom;
  final DateTime? validTo;
  final DateTime retrievedAt;
  final double lat;
  final double lon;

  const MetAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.instruction,
    required this.event,
    required this.severity,
    required this.awarenessLevel,
    required this.awarenessName,
    required this.area,
    this.validFrom,
    this.validTo,
    required this.retrievedAt,
    required this.lat,
    required this.lon,
  });

  /// Whether this warning is in effect during [t].
  bool covers(DateTime t) {
    if (validFrom != null && t.isBefore(validFrom!)) return false;
    if (validTo != null && t.isAfter(validTo!)) return false;
    return true;
  }

  String get levelLabel => switch (awarenessLevel) {
    2 => 'Gult farevarsel',
    3 => 'Oransje farevarsel',
    4 => 'Rødt farevarsel',
    _ => 'Farevarsel',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'desc': description,
    'instruction': instruction,
    'event': event,
    'severity': severity,
    'level': awarenessLevel,
    'levelName': awarenessName,
    'area': area,
    'from': validFrom?.toIso8601String(),
    'to': validTo?.toIso8601String(),
    'retrievedAt': retrievedAt.toIso8601String(),
    'lat': lat,
    'lon': lon,
  };

  factory MetAlert.fromJson(Map<String, dynamic> j) => MetAlert(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['desc'] as String? ?? '',
    instruction: j['instruction'] as String? ?? '',
    event: j['event'] as String? ?? '',
    severity: j['severity'] as String? ?? '',
    awarenessLevel: j['level'] as int? ?? 1,
    awarenessName: j['levelName'] as String? ?? '',
    area: j['area'] as String? ?? '',
    validFrom: j['from'] != null ? DateTime.tryParse(j['from']) : null,
    validTo: j['to'] != null ? DateTime.tryParse(j['to']) : null,
    retrievedAt: j['retrievedAt'] != null
        ? DateTime.tryParse(j['retrievedAt']) ?? DateTime.now()
        : DateTime.now(),
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lon: (j['lon'] as num?)?.toDouble() ?? 0,
  );
}
