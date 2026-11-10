import 'packing.dart';
import 'trip.dart';

/// Forecast/season-driven weather signals the packing rules react to.
enum WeatherFlag { rain, strongWind, snow, cold }

/// How certain the app is that the route crosses avalanche terrain.
/// [uncertain] means winter/ski conditions exist but the user has not
/// confirmed the terrain — gear is included with an explicit caveat.
enum AvalancheRisk { none, uncertain, yes }

extension AvalancheRiskX on AvalancheRisk {
  String get label => switch (this) {
    AvalancheRisk.none => 'Utenfor skredterreng',
    AvalancheRisk.uncertain => 'Ukjent – anta mulig skred',
    AvalancheRisk.yes => 'Mulig skredterreng',
  };
}

/// Everything the rule engine needs to know about the trip. Built by
/// [PackingEngine] from the trip, the weather forecast and the profile.
class TripConditions {
  final TripActivity activity;
  final CarryMode carry;
  final AccommodationType accommodation;

  /// Staffed/self-service/unstaffed — only read by cabin rules.
  final CabinType cabinType;

  /// Cabin type per night (empty when unknown) – see [Trip.cabinNights].
  final List<CabinType> cabinNights;
  final TripSeason season;
  final int days;
  final int people;

  /// Children within [people] — adds spare clothes and snacks.
  final int children;

  /// Lowest expected temperature, or null when no forecast exists.
  /// Unknown is NEVER treated as warm: items gated on cold keep being
  /// suggested, warm-only extras are left out.
  ///
  /// When [minTempEstimated] is true, the value includes about 0.65 °C
  /// per 100 m between the forecast altitude and the route high point.
  /// It is a planning estimate, not a measured temperature.
  final double? minTemp;
  final bool minTempEstimated;
  final bool rain;

  /// One forecast hour ≥ 5 mm, or ≥ 15 mm in the stage window.
  final bool heavyRain;
  final bool strongWind;

  /// Sustained ≥ 17.2 m/s or gusts ≥ 25 m/s.
  final bool storm;
  final bool snow;
  final bool cold;
  final bool darkEvenings;

  /// Deepest modelled snow along the route (seNorge), null when not
  /// fetched.
  final double? snowDepthCm;
  final AvalancheRisk avalanche;

  final bool withDog;
  final bool lightPacker;
  final bool extraComfort;
  final bool coldSensitive;
  final bool ownsTent;
  final bool ownsStove;
  final SkiStyle skiStyle;
  final bool snowshoes;
  final bool fishing;

  /// Steepest local grade from the elevation profile, in degrees.
  /// Null when the profile has no close samples. Not an NVE raster value.
  final double? maxSlopeDegrees;

  const TripConditions({
    required this.activity,
    required this.carry,
    required this.accommodation,
    this.cabinType = CabinType.selfService,
    this.cabinNights = const [],
    required this.season,
    required this.days,
    required this.people,
    this.children = 0,
    this.minTemp,
    this.minTempEstimated = false,
    this.rain = false,
    this.heavyRain = false,
    this.strongWind = false,
    this.storm = false,
    this.snow = false,
    this.cold = false,
    this.darkEvenings = false,
    this.snowDepthCm,
    this.avalanche = AvalancheRisk.none,
    this.withDog = false,
    this.lightPacker = false,
    this.extraComfort = false,
    this.coldSensitive = false,
    this.ownsTent = true,
    this.ownsStove = true,
    this.skiStyle = SkiStyle.fjellski,
    this.snowshoes = false,
    this.fishing = false,
    this.maxSlopeDegrees,
  });

  bool get overnight => accommodation != AccommodationType.dayHike;
  bool get mixed => accommodation == AccommodationType.mixed;
  bool get tent => accommodation == AccommodationType.tent || mixed;
  bool get cabinBase => accommodation == AccommodationType.cabinBase;
  bool get cabin =>
      accommodation == AccommodationType.cabin || mixed || cabinBase;
  bool get multiDay => days > 1;

  /// Cabin types the group sleeps in.
  Set<CabinType> get cabinTypesUsed =>
      cabinNights.isEmpty ? {cabinType} : cabinNights.toSet();

  /// Hut-to-hut trip where the cabins differ from night to night.
  bool get variedCabins => cabinTypesUsed.length > 1;

  /// «natt 1 og 2» – the nights spent in a cabin of one of [types].
  String nightsIn(Set<CabinType> types) {
    final n = [
      for (var i = 0; i < cabinNights.length; i++)
        if (types.contains(cabinNights[i])) '${i + 1}',
    ];
    if (n.isEmpty) return '';
    final list = n.length == 1
        ? n.first
        : '${n.sublist(0, n.length - 1).join(', ')} og ${n.last}';
    return 'natt $list';
  }

  /// «natt 1 og 2 selvbetjent, natt 3 betjent».
  String get cabinSummary => [
    for (final t in cabinTypesUsed) '${nightsIn({t})} ${t.label.toLowerCase()}',
  ].join(', ');

  /// Snow or a known forecast at/below freezing — real winter camping.
  /// Shoulder-season cold alone (spring/autumn) is not enough.
  bool get winterCamp => snow || (minTemp != null && minTemp! <= 0);

  bool has(WeatherFlag f) => switch (f) {
    WeatherFlag.rain => rain,
    WeatherFlag.strongWind => strongWind,
    WeatherFlag.snow => snow,
    WeatherFlag.cold => cold,
  };
}

/// One entry in the master gear catalog. An item is included only when
/// every declarative rule matches the trip conditions; [extra] is an
/// optional escape hatch for conditions that don't fit a field.
///
/// Semantics of the temperature gates:
/// - [onlyAtOrBelowC]: include when the lowest expected temperature is at
///   or below the value — or when it is UNKNOWN (conservative).
/// - [onlyAtOrAboveC]: include only when a forecast exists and is at or
///   above the value.
/// - [warmExcluded] removes the item for those activities when a known
///   forecast says 15 °C or more (e.g. no down jacket on a summer ride).
class GearItem {
  final String id;
  final String name;
  final PackingCategory category;
  final double grams;
  final PackingPriority priority;
  final bool perPerson;
  final double qty;
  final double? qtyOvernight;

  /// Multiply quantity by trip length (e.g. dog food per day).
  final bool qtyPerDay;

  /// Overrides the computed quantity (e.g. one tent per two people).
  final double Function(TripConditions)? qtyFn;
  final bool worn;
  final bool consumable;
  final String? reason;
  final String Function(TripConditions)? reasonFn;

  // ── Strict include/exclude rules ─────────────────────────
  final Set<TripActivity> activities;
  final Set<TripActivity> excludeActivities;
  final Set<CarryMode> carryModes;
  final Set<CarryMode> excludeCarry;
  final Set<AccommodationType> accommodation;
  final Set<AccommodationType> excludeAccommodation;
  final Set<CabinType> cabinTypes;
  final Set<TripSeason> seasons;
  final int minDays;
  final Set<WeatherFlag> needsWeather;
  final Set<WeatherFlag> anyWeather;

  /// Include only when a single hour or the window total is heavy rain.
  final bool heavyRainOnly;

  /// Include only in near-gale / storm, not in a fresh breeze.
  final bool stormOnly;
  final double? onlyAtOrBelowC;
  final double? onlyAtOrAboveC;
  final Set<TripActivity> warmExcluded;
  final bool dogOnly;
  final bool comfortOnly;
  final bool coldSensitiveOnly;
  final bool needsAvalanche;
  final bool Function(TripConditions)? extra;

  // ── Priority boosts (item stays, priority rises) ─────────
  final PackingPriority? boostTo;
  final bool boostOnCold;
  final bool boostOnRain;
  final bool boostOnWind;
  final bool boostOnDark;
  final bool boostOnOvernight;
  final double? boostBelowC;

  const GearItem(
    this.id,
    this.name,
    this.category,
    this.grams, {
    this.priority = PackingPriority.recommended,
    this.perPerson = false,
    this.qty = 1,
    this.qtyOvernight,
    this.qtyPerDay = false,
    this.qtyFn,
    this.worn = false,
    this.consumable = false,
    this.reason,
    this.reasonFn,
    this.activities = const {},
    this.excludeActivities = const {},
    this.carryModes = const {},
    this.excludeCarry = const {},
    this.accommodation = const {},
    this.excludeAccommodation = const {},
    this.cabinTypes = const {},
    this.seasons = const {},
    this.minDays = 1,
    this.needsWeather = const {},
    this.anyWeather = const {},
    this.heavyRainOnly = false,
    this.stormOnly = false,
    this.onlyAtOrBelowC,
    this.onlyAtOrAboveC,
    this.warmExcluded = const {},
    this.dogOnly = false,
    this.comfortOnly = false,
    this.coldSensitiveOnly = false,
    this.needsAvalanche = false,
    this.extra,
    this.boostTo,
    this.boostOnCold = false,
    this.boostOnRain = false,
    this.boostOnWind = false,
    this.boostOnDark = false,
    this.boostOnOvernight = false,
    this.boostBelowC,
  });

  bool matches(TripConditions c) {
    // Running shares the hiking rule set — same terrain and weather,
    // just quicker.
    final activity = c.activity == TripActivity.run
        ? TripActivity.foot
        : c.activity;
    if (activities.isNotEmpty &&
        !activities.contains(activity) &&
        !activities.contains(c.activity)) {
      return false;
    }
    if (excludeActivities.contains(activity) ||
        excludeActivities.contains(c.activity)) {
      return false;
    }
    // A kayak carries the canoe kit (dry bags, vest, spare paddle) and
    // adds its own items via [extra]; rules written for canoe apply.
    final carry = c.carry == CarryMode.kayak ? CarryMode.canoe : c.carry;
    if (carryModes.isNotEmpty &&
        !carryModes.contains(carry) &&
        !carryModes.contains(c.carry)) {
      return false;
    }
    if (excludeCarry.contains(carry) || excludeCarry.contains(c.carry)) {
      return false;
    }
    // A cabin base follows the cabin rules; a mixed trip (tent some
    // nights, cabin others) needs both kits.
    final acc = c.cabinBase ? AccommodationType.cabin : c.accommodation;
    if (accommodation.isNotEmpty &&
        !accommodation.contains(acc) &&
        !accommodation.contains(c.accommodation) &&
        !(c.mixed &&
            (accommodation.contains(AccommodationType.tent) ||
                accommodation.contains(AccommodationType.cabin)))) {
      return false;
    }
    if (excludeAccommodation.contains(acc) ||
        excludeAccommodation.contains(c.accommodation)) {
      return false;
    }
    if (cabinTypes.isNotEmpty && !c.cabinTypesUsed.any(cabinTypes.contains)) {
      return false;
    }
    if (seasons.isNotEmpty && !seasons.contains(c.season)) return false;
    if (c.days < minDays) return false;
    if (needsWeather.any((f) => !c.has(f))) return false;
    if (anyWeather.isNotEmpty && !anyWeather.any(c.has)) return false;
    if (heavyRainOnly && !c.heavyRain) return false;
    if (stormOnly && !c.storm) return false;
    // Cold-gated gear: unknown temperature stays included on purpose.
    if (onlyAtOrBelowC != null &&
        c.minTemp != null &&
        c.minTemp! > onlyAtOrBelowC!) {
      return false;
    }
    // Warm-gated gear: unknown temperature is NOT treated as warm.
    if (onlyAtOrAboveC != null &&
        (c.minTemp == null || c.minTemp! < onlyAtOrAboveC!)) {
      return false;
    }
    if (warmExcluded.contains(c.activity) &&
        c.minTemp != null &&
        c.minTemp! >= 15) {
      return false;
    }
    if (dogOnly && !c.withDog) return false;
    if (comfortOnly && !c.extraComfort) return false;
    if (coldSensitiveOnly && !c.coldSensitive) return false;
    if (needsAvalanche && c.avalanche == AvalancheRisk.none) return false;
    if (extra != null && !extra!(c)) return false;
    return true;
  }

  PackingPriority priorityFor(TripConditions c) {
    if (boostTo == null) return priority;
    final boosted =
        (boostOnCold && c.cold) ||
        (boostOnRain && c.rain) ||
        (boostOnWind && c.strongWind) ||
        (boostOnDark && c.darkEvenings) ||
        (boostOnOvernight && c.overnight) ||
        (boostBelowC != null &&
            c.minTemp != null &&
            c.minTemp! <= boostBelowC!);
    return boosted ? boostTo! : priority;
  }

  /// Builds the packing item. The catalog [id] becomes the item id —
  /// stable identity is what lets packed state, user edits and
  /// tombstones survive regeneration and sync.
  PackingItem toItem(TripConditions c) {
    var q = qty;
    if (c.overnight && qtyOvernight != null) q = qtyOvernight!;
    if (perPerson) q *= c.people;
    if (qtyPerDay) q *= c.days;
    if (qtyFn != null) q = qtyFn!(c);
    return PackingItem(
      id: id,
      name: name,
      category: category,
      quantity: q,
      unitWeightGrams: grams,
      priority: priorityFor(c),
      worn: worn,
      consumable: consumable,
      reason: reasonFn?.call(c) ?? reason,
      needsAcquisition:
          (reasonFn?.call(c) ?? reason)?.contains('må lånes') ?? false,
    );
  }
}
