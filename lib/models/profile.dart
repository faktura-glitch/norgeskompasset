import 'dart:convert';

import 'trip.dart' show TripSeason;

/// Self-assessed touring level — drives the "kan du klare turen?"
/// assessment that compares stage demands against what the user
/// says they can handle.
enum TourLevel { novice, intermediate, experienced }

extension TourLevelX on TourLevel {
  String get label => switch (this) {
    TourLevel.novice => 'Nybegynner',
    TourLevel.intermediate => 'Middels erfaren',
    TourLevel.experienced => 'Erfaren',
  };

  /// Comfortable daily limits (km / ascent m) in mountain terrain —
  /// conservative planning figures, not guarantees.
  double get maxKmPerDay => switch (this) {
    TourLevel.novice => 12,
    TourLevel.intermediate => 18,
    TourLevel.experienced => 26,
  };
  double get maxAscentPerDay => switch (this) {
    TourLevel.novice => 500,
    TourLevel.intermediate => 900,
    TourLevel.experienced => 1500,
  };
}

/// App-level personal profile. Trip-independent — it travels with the
/// user across trips and sharpens generated packing lists, meal plans
/// and the safety card shared with emergency contacts.
class UserProfile {
  String name;
  String phone;

  /// User reports getting cold easily — packing boosts insulation.
  bool coldSensitive;

  /// Vegetarian default applied to newly generated meal plans.
  bool vegetarian;

  /// Fully vegan — supersedes [vegetarian] when set.
  bool vegan;

  /// Dietary tags surfaced on meal plans and shopping lists.
  bool glutenFree;
  bool lactoseFree;
  bool nutAllergy;

  /// Prefers freeze-dried/expedition meals over cooking from
  /// regular ingredients.
  bool prefersDehydrated;

  /// Ultralight packer — swaps tent for tarp and drops "nice to
  /// have" items from generated packing lists.
  bool lightPacker;

  /// Wants extra camp comfort — adds chair, camp shoes, pillow,
  /// good coffee to generated lists.
  bool extraComfort;

  /// Brings a dog — adds leash, paw protection, dog food, bowl
  /// and optionally a pack saddle (kløv).
  bool withDog;

  /// Whether the user owns core group gear. When false the packing
  /// list flags the item as "must be acquired or borrowed".
  bool ownsTent;
  bool ownsStove;

  /// Preferred trip season — used as the default when creating a
  /// new trip so lists start with the right assumptions.
  TripSeason? preferredSeason;

  /// Emergency contact (ICE) — name and phone, surfaced on the
  /// trip's safety card so it can be shared with next of kin.
  String iceName;
  String icePhone;

  /// Allergies, medication or other medical notes worth sharing with
  /// rescue contacts — surfaced on the trip's safety card.
  String medicalNotes;

  /// Body weight in kg — feeds the daily energy estimate on the
  /// meal plan. 0 means "not set" (75 kg fallback is used).
  double weightKg;

  /// Self-assessed touring level. Null means "not set" — the trip
  /// suitability assessment only runs once the user picks a level.
  TourLevel? level;

  UserProfile({
    this.name = '',
    this.phone = '',
    this.coldSensitive = false,
    this.vegetarian = false,
    this.vegan = false,
    this.glutenFree = false,
    this.lactoseFree = false,
    this.nutAllergy = false,
    this.prefersDehydrated = false,
    this.lightPacker = false,
    this.extraComfort = false,
    this.withDog = false,
    this.ownsTent = true,
    this.ownsStove = true,
    this.preferredSeason,
    this.iceName = '',
    this.icePhone = '',
    this.medicalNotes = '',
    this.weightKg = 0,
    this.level,
  });

  /// Dietary restrictions that affect meal planning.
  List<String> get dietTags => [
    if (vegan) 'Vegansk',
    if (vegetarian && !vegan) 'Vegetar',
    if (glutenFree) 'Glutenfri',
    if (lactoseFree) 'Laktosefri',
    if (nutAllergy) 'Nøtteallergi',
  ];

  bool get isEmpty =>
      name.isEmpty &&
      phone.isEmpty &&
      !coldSensitive &&
      !vegetarian &&
      !vegan &&
      !glutenFree &&
      !lactoseFree &&
      !nutAllergy &&
      !prefersDehydrated &&
      !lightPacker &&
      !extraComfort &&
      !withDog &&
      iceName.isEmpty &&
      icePhone.isEmpty &&
      medicalNotes.isEmpty &&
      weightKg <= 0 &&
      preferredSeason == null &&
      level == null;

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'coldSensitive': coldSensitive,
    'vegetarian': vegetarian,
    'vegan': vegan,
    'glutenFree': glutenFree,
    'lactoseFree': lactoseFree,
    'nutAllergy': nutAllergy,
    'prefersDehydrated': prefersDehydrated,
    'lightPacker': lightPacker,
    'extraComfort': extraComfort,
    'withDog': withDog,
    'ownsTent': ownsTent,
    'ownsStove': ownsStove,
    'preferredSeason': preferredSeason?.name,
    'iceName': iceName,
    'icePhone': icePhone,
    'medicalNotes': medicalNotes,
    'weightKg': weightKg,
    'level': level?.name,
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    coldSensitive: j['coldSensitive'] as bool? ?? false,
    vegetarian: j['vegetarian'] as bool? ?? false,
    vegan: j['vegan'] as bool? ?? false,
    glutenFree: j['glutenFree'] as bool? ?? false,
    lactoseFree: j['lactoseFree'] as bool? ?? false,
    nutAllergy: j['nutAllergy'] as bool? ?? false,
    prefersDehydrated: j['prefersDehydrated'] as bool? ?? false,
    lightPacker: j['lightPacker'] as bool? ?? false,
    extraComfort: j['extraComfort'] as bool? ?? false,
    withDog: j['withDog'] as bool? ?? false,
    ownsTent: j['ownsTent'] as bool? ?? true,
    ownsStove: j['ownsStove'] as bool? ?? true,
    preferredSeason: TripSeason.values.asNameMap()[j['preferredSeason']],
    iceName: j['iceName'] as String? ?? '',
    icePhone: j['icePhone'] as String? ?? '',
    medicalNotes: j['medicalNotes'] as String? ?? '',
    weightKg: (j['weightKg'] as num?)?.toDouble() ?? 0,
    level: switch (j['level'] as String?) {
      'novice' => TourLevel.novice,
      'intermediate' => TourLevel.intermediate,
      'experienced' => TourLevel.experienced,
      _ => null,
    },
  );

  String encode() => jsonEncode(toJson());
  factory UserProfile.decode(String s) => UserProfile.fromJson(jsonDecode(s));
}
