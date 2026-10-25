/// An avalanche warning from NVE's Varsom API (api01.nve.no).
/// Warnings are per region and day, published a few days ahead and
/// only during the avalanche season (~Nov–Jun).
class AvalancheWarning {
  final String regId;
  final String regionName;
  final int dangerLevel; // 0–5 per EAWS scale
  final DateTime? validFrom;
  final DateTime? validTo;
  final String mainText;
  final DateTime? publishTime;
  final double lat;
  final double lon;

  const AvalancheWarning({
    required this.regId,
    required this.regionName,
    required this.dangerLevel,
    this.validFrom,
    this.validTo,
    this.mainText = '',
    this.publishTime,
    required this.lat,
    required this.lon,
  });

  /// Norwegian danger-level label per the standard EAWS naming.
  String get levelLabel => switch (dangerLevel) {
        0 => 'Ikke vurdert',
        1 => '1 – Liten',
        2 => '2 – Moderat',
        3 => '3 – Betydelig',
        4 => '4 – Stor',
        _ => '5 – Meget stor',
      };

  Map<String, dynamic> toJson() => {
        'regId': regId,
        'region': regionName,
        'level': dangerLevel,
        'from': validFrom?.toIso8601String(),
        'to': validTo?.toIso8601String(),
        'text': mainText,
        'published': publishTime?.toIso8601String(),
        'lat': lat,
        'lon': lon,
      };

  factory AvalancheWarning.fromJson(Map<String, dynamic> j) =>
      AvalancheWarning(
        regId: j['regId']?.toString() ?? '',
        regionName: j['region'] as String? ?? '',
        dangerLevel: j['level'] as int? ?? 0,
        validFrom: j['from'] != null
            ? DateTime.tryParse(j['from'].toString())
            : null,
        validTo: j['to'] != null
            ? DateTime.tryParse(j['to'].toString())
            : null,
        mainText: j['text'] as String? ?? '',
        publishTime: j['published'] != null
            ? DateTime.tryParse(j['published'].toString())
            : null,
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0,
      );

  /// Parses one entry of the Varsom Simple response format.
  factory AvalancheWarning.fromVarsomJson(
      Map<String, dynamic> j, double lat, double lon) {
    return AvalancheWarning(
      regId: j['RegId']?.toString() ?? '',
      regionName: j['RegionName'] as String? ?? '',
      dangerLevel: int.tryParse(j['DangerLevel']?.toString() ?? '') ?? 0,
      validFrom: j['ValidFrom'] != null
          ? DateTime.tryParse(j['ValidFrom'].toString())
          : null,
      validTo: j['ValidTo'] != null
          ? DateTime.tryParse(j['ValidTo'].toString())
          : null,
      mainText: (j['MainText'] as String? ?? '').trim(),
      publishTime: j['PublishTime'] != null
          ? DateTime.tryParse(j['PublishTime'].toString())
          : null,
      lat: lat,
      lon: lon,
    );
  }
}
