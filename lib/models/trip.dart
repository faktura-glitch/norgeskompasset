import 'dart:convert';

import 'alert.dart';
import 'avalanche.dart';
import 'meal.dart';
import 'packing.dart';
import 'recommendation.dart';
import 'route_models.dart';
import 'stage.dart';
import 'track.dart';
import 'weather.dart';
import '../services/stage_builder.dart';

enum TripStatus { draft, planned, active, completed }

extension TripStatusX on TripStatus {
  String get label => switch (this) {
    TripStatus.draft => 'Utkast',
    TripStatus.planned => 'Planlagt',
    TripStatus.active => 'På tur',
    TripStatus.completed => 'Gjennomført',
  };
}

/// [cabinBase]: the group sleeps in one cabin and does day trips from
/// it — cabin kit plus a small daypack, no tent.
enum AccommodationType { tent, cabin, dayHike, mixed, cabinBase }

extension AccommodationTypeX on AccommodationType {
  String get label => switch (this) {
    AccommodationType.tent => 'Telt',
    AccommodationType.cabin => 'Hytte',
    AccommodationType.dayHike => 'Dagstur',
    AccommodationType.mixed => 'Telt og hytte',
    AccommodationType.cabinBase => 'Hyttebase',
  };

  /// Whether this accommodation type involves at least one cabin night.
  bool get usesCabin =>
      this == AccommodationType.cabin ||
      this == AccommodationType.mixed ||
      this == AccommodationType.cabinBase;
}

/// Type of staffed/self-service/unstaffed cabin (DNT model). Only
/// meaningful when [AccommodationType.usesCabin]: a staffed cabin serves
/// meals, an unstaffed one requires carrying all food and paying by
/// Vipps/cash.
enum CabinType { staffed, selfService, unstaffed }

extension CabinTypeX on CabinType {
  String get label => switch (this) {
    CabinType.staffed => 'Betjent',
    CabinType.selfService => 'Selvbetjent',
    CabinType.unstaffed => 'Ubetjent',
  };
}

/// Kind of ski trip — decides skins, helmet and whether the
/// avalanche trio is relevant at all (not in prepared tracks).
enum SkiStyle { fjellski, touring, track }

extension SkiStyleX on SkiStyle {
  String get label => switch (this) {
    SkiStyle.fjellski => 'Fjellski',
    SkiStyle.touring => 'Topptur',
    SkiStyle.track => 'Langrenn i løyper',
  };
}

/// Season changes what the packing engine assumes regardless of
/// forecast — shoulder seasons are cold in the mountains and winter
/// may mean avalanche terrain even when no warning is currently
/// issued. A 9-day forecast can't cover a trip planned months ahead.
enum TripSeason { spring, summer, autumn, winter }

extension TripSeasonX on TripSeason {
  String get label => switch (this) {
    TripSeason.spring => 'Vår',
    TripSeason.summer => 'Sommer',
    TripSeason.autumn => 'Høst',
    TripSeason.winter => 'Vinter',
  };
}

/// How the group carries its gear — a sled (pulk) or a canoe changes
/// packing fundamentally (dry bags, spare paddle, life vests).
enum CarryMode { backpack, pulk, canoe, kayak, bikeBags }

extension CarryModeX on CarryMode {
  String get label => switch (this) {
    CarryMode.backpack => 'Sekk',
    CarryMode.pulk => 'Pulk',
    CarryMode.canoe => 'Kano',
    CarryMode.kayak => 'Kajakk',
    CarryMode.bikeBags => 'Sykkelvesker',
  };

  /// Canoe and kayak share the paddling kit (dry bags, vest, spare
  /// paddle); kayak adds its own items on top.
  bool get isPaddle => this == CarryMode.canoe || this == CarryMode.kayak;
}

/// How the group moves — on foot, skis, bike or paddle. The choice
/// selects the routing profile (trails / pistes / cycleways /
/// waterways), the map overlay to show and the packing-gear branch.
enum TripActivity { foot, run, ski, bike, paddle }

extension TripActivityX on TripActivity {
  String get label => switch (this) {
    TripActivity.foot => 'Fottur',
    TripActivity.run => 'Løping',
    TripActivity.ski => 'Ski',
    TripActivity.bike => 'Sykkel',
    TripActivity.paddle => 'Padling',
  };

  /// Running uses the trail network and the hiking packing rules
  /// (lighter, but the same terrain and weather).
  bool get onFoot => this == TripActivity.foot || this == TripActivity.run;
}

enum HikingPace { relaxed, normal, brisk }

extension HikingPaceX on HikingPace {
  String get label => switch (this) {
    HikingPace.relaxed => 'Rolig',
    HikingPace.normal => 'Normalt',
    HikingPace.brisk => 'Raskt',
  };

  /// Multiplier applied to base hiking-time estimate (1.0 = normal).
  double get timeFactor => switch (this) {
    HikingPace.relaxed => 1.25,
    HikingPace.normal => 1.0,
    HikingPace.brisk => 0.85,
  };
}

/// Post-trip review captured for learning.
class TripReview {
  double? actualDistanceKm;
  double? actualDurationHours;
  double? actualAscent;
  String weatherExperienced;
  List<String> workedWell;
  List<String> unnecessary;
  List<String> missing;
  String difficultSections;
  String notes;
  int rating; // 1-5
  DateTime? completedAt;

  TripReview({
    this.actualDistanceKm,
    this.actualDurationHours,
    this.actualAscent,
    this.weatherExperienced = '',
    this.workedWell = const [],
    this.unnecessary = const [],
    this.missing = const [],
    this.difficultSections = '',
    this.notes = '',
    this.rating = 3,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'distance': actualDistanceKm,
    'duration': actualDurationHours,
    'ascent': actualAscent,
    'weather': weatherExperienced,
    'workedWell': workedWell,
    'unnecessary': unnecessary,
    'missing': missing,
    'difficult': difficultSections,
    'notes': notes,
    'rating': rating,
    'completedAt': completedAt?.toIso8601String(),
  };

  factory TripReview.fromJson(Map<String, dynamic> j) => TripReview(
    actualDistanceKm: (j['distance'] as num?)?.toDouble(),
    actualDurationHours: (j['duration'] as num?)?.toDouble(),
    actualAscent: (j['ascent'] as num?)?.toDouble(),
    weatherExperienced: j['weather'] as String? ?? '',
    workedWell: (j['workedWell'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    unnecessary: (j['unnecessary'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    missing: (j['missing'] as List? ?? []).map((e) => e.toString()).toList(),
    difficultSections: j['difficult'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    rating: j['rating'] as int? ?? 3,
    completedAt: j['completedAt'] != null
        ? DateTime.tryParse(j['completedAt'])
        : null,
  );
}

class Trip {
  String id;
  String name;
  DateTime? startDate;
  DateTime? endDate;

  /// When the user told someone they'd be back. The hiking screen
  /// warns once this time has passed while tracking is active.
  DateTime? expectedReturn;
  TripStatus status;
  AccommodationType accommodation;

  /// Only meaningful when [accommodation] involves a cabin
  /// ([AccommodationType.usesCabin]) — decides food, payment and
  /// booking gear in the packing list.
  CabinType cabinType;

  /// Cabin type per night on a hut-to-hut trip (index 0 = night 1).
  /// Empty means every night uses [cabinType].
  List<CabinType> nightCabins;

  /// Cabin type for each night in a cabin, or empty when the nights
  /// are not known to be cabin nights (day trip, tent, mixed).
  List<CabinType> get cabinNights {
    if (accommodation != AccommodationType.cabin &&
        accommodation != AccommodationType.cabinBase) {
      return const [];
    }
    final perNight = accommodation == AccommodationType.cabin;
    return [
      for (var i = 0; i < hikingDays - 1; i++)
        perNight && i < nightCabins.length ? nightCabins[i] : cabinType,
    ];
  }

  /// «Hytte: 2 selvbetjent, 1 betjent» when the nights differ, else
  /// the plain accommodation label.
  String get accommodationLabel {
    final nights = cabinNights;
    final types = nights.toSet();
    if (types.length < 2) return accommodation.label;
    final counts = [
      for (final t in types) (nights.where((n) => n == t).length, t),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return 'Hytte: ${[for (final (n, t) in counts) '$n ${t.label.toLowerCase()}'].join(', ')}';
  }

  TripSeason season;
  CarryMode carry;
  HikingPace pace;
  TripActivity activity;
  int participants;

  /// Dog on this trip; null follows the profile setting.
  bool? withDog;

  /// Children in the group (counted within [participants]). Slows the
  /// pace and adds spare clothes/snacks to the packing list.
  int children;

  /// Only meaningful when [activity] is ski.
  SkiStyle skiStyle;

  /// Snowshoes on a winter foot trip.
  bool snowshoes;

  /// Fishing along the way — adds rod, licence reminder and knife.
  bool fishing;
  String notes;
  String? localTourId;
  HikingRoute? route;
  List<Stage> stages;
  List<PackingItem> packingList;
  MealPlan? mealPlan;
  List<Recommendation> recommendations;
  List<MetAlert> alerts;

  /// Avalanche warnings (Varsom/NVE) covering the route area and
  /// trip dates. Empty outside the warning season.
  List<AvalancheWarning> avalancheWarnings;

  /// User-confirmed terrain assessment: true = route may cross avalanche
  /// terrain, false = confirmed outside it, null = unknown. Unknown is
  /// treated as uncertain for winter/ski trips — avalanche gear is then
  /// suggested with an explicit caveat instead of silently omitted.
  bool? avalancheTerrain;
  TripReview? review;

  /// GPS positions recorded during active hiking mode.
  List<TrackPoint> trackLog;

  /// Catalog ids of generated packing suggestions the user has
  /// dismissed. Tombstones survive regeneration and sync so a removed
  /// suggestion never silently reappears.
  Set<String> deletedGearIds;

  /// Weather snapshots keyed by stage id (or 'route' for whole-route point).
  Map<String, WeatherSnapshot> weather;

  DateTime createdAt;
  DateTime updatedAt;
  DateTime? lastSharedAt;

  /// Share code in the sharedTrips collection — set when the trip was
  /// published for others, or when this copy was fetched via a code.
  /// Lets a fetched copy re-pull the owner's latest version.
  String? shareCode;

  Trip({
    required this.id,
    this.name = '',
    this.startDate,
    this.endDate,
    this.expectedReturn,
    this.status = TripStatus.draft,
    this.accommodation = AccommodationType.dayHike,
    this.cabinType = CabinType.selfService,
    this.nightCabins = const [],
    this.season = TripSeason.summer,
    this.carry = CarryMode.backpack,
    this.pace = HikingPace.normal,
    this.activity = TripActivity.foot,
    this.participants = 1,
    this.withDog,
    this.children = 0,
    this.skiStyle = SkiStyle.fjellski,
    this.snowshoes = false,
    this.fishing = false,
    this.notes = '',
    this.localTourId,
    this.route,
    this.stages = const [],
    this.packingList = const [],
    this.mealPlan,
    this.recommendations = const [],
    this.alerts = const [],
    this.avalancheWarnings = const [],
    this.avalancheTerrain,
    this.review,
    this.trackLog = const [],
    Set<String>? deletedGearIds,
    Map<String, WeatherSnapshot>? weather,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastSharedAt,
    this.shareCode,
  }) : weather = weather ?? {},
       deletedGearIds = deletedGearIds ?? {},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  int get hikingDays {
    if (startDate != null && endDate != null) {
      return endDate!.difference(startDate!).inDays + 1;
    }
    return stages.isNotEmpty ? stages.length : 1;
  }

  /// Packed share of the list by carried weight — matches the
  /// packing screen's kg-based progress. Worn items (boots etc.)
  /// are excluded: they go on the body, not in the pack.
  double get packingCompletion {
    final pack = packingList.where((i) => !i.worn).toList();
    final total = pack.fold(0.0, (s, i) => s + i.totalWeightGrams);
    if (total <= 0) {
      if (packingList.isEmpty) return 0;
      final packed = packingList.where((i) => i.packed).length;
      return packed / packingList.length;
    }
    final packedG = pack
        .where((i) => i.packed)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    return packedG / total;
  }

  /// Sum of all stage time estimates — 0 before stages are built.
  double get totalEstimatedMinutes =>
      stages.fold(0.0, (s, st) => s + st.estimatedMinutes);

  int get packedCount => packingList.where((i) => i.packed).length;

  /// Required items still to go in the pack. Worn items (boots, hiking
  /// clothes) never sit in the pack, so they are not counted as missing.
  int get missingRequiredCount => packingList.missingRequired.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'expectedReturn': expectedReturn?.toIso8601String(),
    'status': status.name,
    'accommodation': accommodation.name,
    if (accommodation.usesCabin) 'cabinType': cabinType.name,
    if (accommodation == AccommodationType.cabin && nightCabins.isNotEmpty)
      'nightCabins': [for (final c in nightCabins) c.name],
    'season': season.name,
    'carry': carry.name,
    'pace': pace.name,
    'activity': activity.name,
    'participants': participants,
    if (withDog != null) 'withDog': withDog,
    if (children > 0) 'children': children,
    if (skiStyle != SkiStyle.fjellski) 'skiStyle': skiStyle.name,
    if (snowshoes) 'snowshoes': true,
    if (fishing) 'fishing': true,
    'notes': notes,
    if (localTourId != null) 'localTourId': localTourId,
    'route': route?.toJson(),
    'stages': stages.map((s) => s.toJson()).toList(),
    'packingList': packingList.map((p) => p.toJson()).toList(),
    'mealPlan': mealPlan?.toJson(),
    'recommendations': recommendations.map((r) => r.toJson()).toList(),
    'alerts': alerts.map((a) => a.toJson()).toList(),
    'avalanche': avalancheWarnings.map((a) => a.toJson()).toList(),
    'avalancheTerrain': avalancheTerrain,
    'trackLog': trackLog.map((t) => t.toJson()).toList(),
    if (deletedGearIds.isNotEmpty) 'delGear': deletedGearIds.toList(),
    'review': review?.toJson(),
    'weather': weather.map((k, v) => MapEntry(k, v.toJson())),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastSharedAt': lastSharedAt?.toIso8601String(),
    'shareCode': shareCode,
  };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    startDate: j['startDate'] != null
        ? DateTime.tryParse(j['startDate'])
        : null,
    endDate: j['endDate'] != null ? DateTime.tryParse(j['endDate']) : null,
    expectedReturn: j['expectedReturn'] != null
        ? DateTime.tryParse(j['expectedReturn'])
        : null,
    status: TripStatus.values.asNameMap()[j['status']] ?? TripStatus.draft,
    accommodation:
        AccommodationType.values.asNameMap()[j['accommodation']] ??
        AccommodationType.dayHike,
    cabinType:
        CabinType.values.asNameMap()[j['cabinType']] ?? CabinType.selfService,
    nightCabins: _cabinList(j['nightCabins']),
    season: TripSeason.values.asNameMap()[j['season']] ?? TripSeason.summer,
    carry: CarryMode.values.asNameMap()[j['carry']] ?? CarryMode.backpack,
    pace: HikingPace.values.asNameMap()[j['pace']] ?? HikingPace.normal,
    activity:
        TripActivity.values.asNameMap()[j['activity']] ?? TripActivity.foot,
    participants: j['participants'] as int? ?? 1,
    withDog: j['withDog'] as bool?,
    children: j['children'] as int? ?? 0,
    skiStyle: SkiStyle.values.asNameMap()[j['skiStyle']] ?? SkiStyle.fjellski,
    snowshoes: j['snowshoes'] as bool? ?? false,
    fishing: j['fishing'] as bool? ?? false,
    notes: j['notes'] as String? ?? '',
    localTourId: j['localTourId'] as String?,
    route: j['route'] != null
        ? HikingRoute.fromJson(Map<String, dynamic>.from(j['route']))
        : null,
    stages: (j['stages'] as List? ?? [])
        .map((s) => Stage.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
    packingList: (j['packingList'] as List? ?? [])
        .map((p) => PackingItem.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
    mealPlan: j['mealPlan'] != null
        ? MealPlan.fromJson(Map<String, dynamic>.from(j['mealPlan']))
        : null,
    recommendations: (j['recommendations'] as List? ?? [])
        .map((r) => Recommendation.fromJson(Map<String, dynamic>.from(r)))
        .toList(),
    alerts: (j['alerts'] as List? ?? [])
        .map((a) => MetAlert.fromJson(Map<String, dynamic>.from(a)))
        .toList(),
    avalancheWarnings: (j['avalanche'] as List? ?? [])
        .map((a) => AvalancheWarning.fromJson(Map<String, dynamic>.from(a)))
        .toList(),
    avalancheTerrain: j['avalancheTerrain'] as bool?,
    trackLog: (j['trackLog'] as List? ?? [])
        .map((t) => TrackPoint.fromJson(Map<String, dynamic>.from(t)))
        .toList(),
    deletedGearIds: (j['delGear'] as List? ?? [])
        .map((e) => e.toString())
        .toSet(),
    review: j['review'] != null
        ? TripReview.fromJson(Map<String, dynamic>.from(j['review']))
        : null,
    weather: (j['weather'] as Map? ?? {}).map(
      (k, v) => MapEntry(
        k.toString(),
        WeatherSnapshot.fromJson(Map<String, dynamic>.from(v)),
      ),
    ),
    createdAt: j['createdAt'] != null
        ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: j['updatedAt'] != null
        ? DateTime.tryParse(j['updatedAt']) ?? DateTime.now()
        : DateTime.now(),
    lastSharedAt: j['lastSharedAt'] != null
        ? DateTime.tryParse(j['lastSharedAt'])
        : null,
    shareCode: j['shareCode'] as String?,
  );

  static List<CabinType> _cabinList(Object? raw) => [
    for (final e in raw as List? ?? const [])
      CabinType.values.asNameMap()[e] ?? CabinType.selfService,
  ];

  String encode() => jsonEncode(toJson());
  factory Trip.decode(String s) => Trip.fromJson(jsonDecode(s));

  // ── Compact cloud snapshot (sync schema v2) ────────────────────
  //
  // The cloud document stores trip choices, the route (compact form)
  // and user state — never derived or remote-fetched data. Stages,
  // weather, MET alerts, Varsom warnings, the GPS track and
  // recommendations are all rebuilt or refetched on the receiving
  // device, so they are simply omitted. This keeps documents small
  // and prevents stale forecast data from masquerading as current.

  static const syncVersion = 2;

  Map<String, dynamic> toSyncJson() => {
    'v': syncVersion,
    'id': id,
    'name': name,
    'start': startDate?.toIso8601String(),
    'end': endDate?.toIso8601String(),
    if (expectedReturn != null) 'expRet': expectedReturn!.toIso8601String(),
    'status': status.name,
    'accom': accommodation.name,
    if (accommodation.usesCabin) 'cabType': cabinType.name,
    if (accommodation == AccommodationType.cabin && nightCabins.isNotEmpty)
      'cabNights': [for (final c in nightCabins) c.name],
    'season': season.name,
    'carry': carry.name,
    'pace': pace.name,
    'act': activity.name,
    'part': participants,
    if (withDog != null) 'dog': withDog,
    if (children > 0) 'kids': children,
    if (skiStyle != SkiStyle.fjellski) 'ss': skiStyle.name,
    if (snowshoes) 'tr': true,
    if (fishing) 'fi': true,
    if (notes.isNotEmpty) 'notes': notes,
    if (localTourId != null) 'localTour': localTourId,
    if (route != null) 'route': route!.toCompactJson(),
    'pack': packingList.map((p) => p.toJson()).toList(),
    if (deletedGearIds.isNotEmpty) 'delGear': deletedGearIds.toList(),
    if (mealPlan != null) 'meal': mealPlan!.toJson(),
    if (avalancheTerrain != null) 'avalTerrain': avalancheTerrain,
    if (review != null) 'review': review!.toJson(),
    'created': createdAt.toIso8601String(),
    'updated': updatedAt.toIso8601String(),
    if (lastSharedAt != null) 'shared': lastSharedAt!.toIso8601String(),
    if (shareCode != null) 'share': shareCode,
  };

  /// Rebuilds a trip from a v2 snapshot. Derived data (stages) is
  /// regenerated deterministically; remote data (weather, warnings)
  /// stays empty until refetched — an honest "not fetched" state,
  /// never fabricated.
  factory Trip.fromSyncJson(Map<String, dynamic> j) {
    final trip = Trip(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      startDate: j['start'] != null ? DateTime.tryParse(j['start']) : null,
      endDate: j['end'] != null ? DateTime.tryParse(j['end']) : null,
      expectedReturn: j['expRet'] != null
          ? DateTime.tryParse(j['expRet'])
          : null,
      status: TripStatus.values.asNameMap()[j['status']] ?? TripStatus.draft,
      accommodation:
          AccommodationType.values.asNameMap()[j['accom']] ??
          AccommodationType.dayHike,
      cabinType:
          CabinType.values.asNameMap()[j['cabType']] ?? CabinType.selfService,
      nightCabins: _cabinList(j['cabNights']),
      season: TripSeason.values.asNameMap()[j['season']] ?? TripSeason.summer,
      carry: CarryMode.values.asNameMap()[j['carry']] ?? CarryMode.backpack,
      pace: HikingPace.values.asNameMap()[j['pace']] ?? HikingPace.normal,
      activity: TripActivity.values.asNameMap()[j['act']] ?? TripActivity.foot,
      participants: j['part'] as int? ?? 1,
      withDog: j['dog'] as bool?,
      children: j['kids'] as int? ?? 0,
      skiStyle: SkiStyle.values.asNameMap()[j['ss']] ?? SkiStyle.fjellski,
      snowshoes: j['tr'] as bool? ?? false,
      fishing: j['fi'] as bool? ?? false,
      notes: j['notes'] as String? ?? '',
      localTourId: j['localTour'] as String?,
      route: j['route'] != null
          ? HikingRoute.fromCompactJson(Map<String, dynamic>.from(j['route']))
          : null,
      packingList: (j['pack'] as List? ?? [])
          .map((p) => PackingItem.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      mealPlan: j['meal'] != null
          ? MealPlan.fromJson(Map<String, dynamic>.from(j['meal']))
          : null,
      avalancheTerrain: j['avalTerrain'] as bool?,
      review: j['review'] != null
          ? TripReview.fromJson(Map<String, dynamic>.from(j['review']))
          : null,
      deletedGearIds: (j['delGear'] as List? ?? [])
          .map((e) => e.toString())
          .toSet(),
      createdAt: j['created'] != null
          ? DateTime.tryParse(j['created']) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: j['updated'] != null
          ? DateTime.tryParse(j['updated']) ?? DateTime.now()
          : DateTime.now(),
      lastSharedAt: j['shared'] != null ? DateTime.tryParse(j['shared']) : null,
      shareCode: j['share'] as String?,
    );
    StageBuilder.recompute(trip);
    return trip;
  }

  /// Decodes either sync schema: v2 snapshots and legacy full-trip JSON.
  static Trip decodeAny(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return j['v'] == syncVersion ? Trip.fromSyncJson(j) : Trip.fromJson(j);
  }
}
