import 'dart:convert';

import 'profile.dart';
import 'route_models.dart';
import 'stage.dart';
import 'trip.dart';

/// A published tour suggestion — route + metadata, readable by any
/// signed-in user via the catalogTrips collection. When a user picks
/// one, a regular [Trip] is created from it and packing/meals are
/// generated from that user's own profile and choices.
class CatalogTrip {
  String id;
  String name;
  String description;
  String region;
  HikingRoute route;
  DifficultyLevel difficulty;
  List<TripSeason> seasons;
  TourLevel minLevel;
  AccommodationType accommodation;
  TripActivity activity;
  int durationDays;
  String ownerUid;
  DateTime updatedAt;

  CatalogTrip({
    required this.id,
    required this.ownerUid,
    required this.route,
    this.name = '',
    this.description = '',
    this.region = '',
    this.difficulty = DifficultyLevel.moderate,
    this.seasons = const [TripSeason.summer, TripSeason.autumn],
    this.minLevel = TourLevel.novice,
    this.accommodation = AccommodationType.dayHike,
    this.activity = TripActivity.foot,
    this.durationDays = 1,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Whether the tour is relevant for [season] and suitable for
  /// [level] — ordering: novice < intermediate < experienced.
  bool matches(TripSeason? season, TourLevel? level) {
    if (season != null && !seasons.contains(season)) return false;
    if (level != null && minLevel.index > level.index) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'region': region,
    'route': route.toJson(),
    'difficulty': difficulty.name,
    'seasons': seasons.map((s) => s.name).toList(),
    'minLevel': minLevel.name,
    'accommodation': accommodation.name,
    'activity': activity.name,
    'durationDays': durationDays,
    'owner': ownerUid,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CatalogTrip.fromJson(Map<String, dynamic> j) => CatalogTrip(
    id: j['id'] as String,
    ownerUid: j['owner'] as String? ?? '',
    name: j['name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    region: j['region'] as String? ?? '',
    route: HikingRoute.fromJson(Map<String, dynamic>.from(j['route'] as Map)),
    difficulty:
        DifficultyLevel.values.asNameMap()[j['difficulty']] ??
        DifficultyLevel.moderate,
    seasons: (j['seasons'] as List? ?? [])
        .map((s) => TripSeason.values.asNameMap()[s])
        .whereType<TripSeason>()
        .toList(),
    minLevel: TourLevel.values.asNameMap()[j['minLevel']] ?? TourLevel.novice,
    accommodation:
        AccommodationType.values.asNameMap()[j['accommodation']] ??
        AccommodationType.dayHike,
    activity:
        TripActivity.values.asNameMap()[j['activity']] ?? TripActivity.foot,
    durationDays: ((j['durationDays'] as num?)?.toInt() ?? 1)
        .clamp(1, 14)
        .toInt(),
    updatedAt: j['updatedAt'] != null
        ? DateTime.tryParse(j['updatedAt']) ?? DateTime.now()
        : DateTime.now(),
  );

  String encode() => jsonEncode(toJson());
  factory CatalogTrip.decode(String s) => CatalogTrip.fromJson(jsonDecode(s));
}
