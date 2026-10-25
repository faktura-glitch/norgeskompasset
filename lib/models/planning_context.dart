import 'gear.dart';
import 'route_models.dart';
import 'trip.dart';

/// Quality of an externally fetched input (weather, avalanche warnings).
/// [partial] means data exists but does not cover the whole trip window;
/// [stale] means it is old enough that a refresh is due.
enum DataQuality { good, partial, stale, missing }

/// Why the plan does or does not carry avalanche gear — the basis is
/// shown to the user so a guess is never presented as an assessment.
enum AvalancheBasis {
  /// A Varsom/NVE warning was fetched for the route and dates.
  warning,

  /// The user confirmed the route may cross avalanche terrain.
  userConfirmed,

  /// The user confirmed the route stays outside avalanche terrain.
  userExcluded,

  /// Winter/ski context where avalanche gear would matter, but neither
  /// a warning nor a user answer exists — gear is suggested with a
  /// caveat, never silently omitted.
  notAssessed,

  /// Season and activity make avalanche exposure unlikely.
  notRelevant,
}

extension AvalancheBasisX on AvalancheBasis {
  String get label => switch (this) {
    AvalancheBasis.warning => 'Skredvarsel hentet',
    AvalancheBasis.userConfirmed => 'Skredterreng bekreftet',
    AvalancheBasis.userExcluded => 'Utenfor skredterreng (bekreftet)',
    AvalancheBasis.notAssessed => 'Skredfare ikke vurdert',
    AvalancheBasis.notRelevant => 'Skredfare lite aktuelt',
  };
}

/// Derived bridge between the route/conditions and the generated plans.
/// Built fresh from the trip — never stored, never presented as observed
/// data. [conditions] is the exact object the packing engine used, so the
/// UI and the rules can never drift apart.
class PlanningContext {
  // ── User choices ──────────────────────────────────────────
  final TripActivity activity;
  final CarryMode carry;
  final AccommodationType accommodation;
  final int days;
  final int participants;

  // ── Route facts ───────────────────────────────────────────
  final double? distanceKm;
  final double? totalAscentM;
  final RouteSource? routeSource;
  final bool hasEstimatedLegs;

  /// Share of route points carrying elevation (0-1), null without route.
  /// Ascent is only trustworthy when coverage is high.
  final double? elevationCoverage;

  // ── Weather ───────────────────────────────────────────────
  final DataQuality weatherQuality;
  final double? minTempC;

  // ── Avalanche ─────────────────────────────────────────────
  final AvalancheBasis avalancheBasis;
  final int? maxDangerLevel;

  /// The exact conditions the packing engine filtered on.
  final TripConditions conditions;

  /// Things the user must verify before trusting the plan — honest gaps,
  /// never hidden defaults.
  final List<String> userChecks;

  const PlanningContext({
    required this.activity,
    required this.carry,
    required this.accommodation,
    required this.days,
    required this.participants,
    required this.conditions,
    this.distanceKm,
    this.totalAscentM,
    this.routeSource,
    this.hasEstimatedLegs = false,
    this.elevationCoverage,
    this.weatherQuality = DataQuality.missing,
    this.minTempC,
    this.avalancheBasis = AvalancheBasis.notRelevant,
    this.maxDangerLevel,
    this.userChecks = const [],
  });

  String get routeLabel => switch (routeSource) {
    null => 'Ingen rute',
    RouteSource.trail => 'Rute langs kjente stier',
    RouteSource.mixed => 'Delvis estimert rute',
    RouteSource.manual => 'Importert/manuell rute (ukontrollert)',
    RouteSource.estimated => 'Estimert punktskisse',
  };

  String get weatherLabel => switch (weatherQuality) {
    DataQuality.good => 'Prognose oppdatert',
    DataQuality.partial => 'Prognose dekker ikke hele turen',
    DataQuality.stale => 'Prognose bør oppdateres',
    DataQuality.missing => 'Ingen prognose hentet',
  };
}
