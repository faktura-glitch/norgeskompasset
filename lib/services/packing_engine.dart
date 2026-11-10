import 'package:uuid/uuid.dart';

import '../core/geo.dart';
import '../models/gear.dart';
import '../models/packing.dart';
import '../models/profile.dart';
import '../models/trip.dart';
import 'gear_catalog.dart';
import 'trip_analysis.dart';

/// Rule-based packing list generator. Every generated item carries a
/// [reason] tying it to actual trip conditions. Weights are typical
/// mid-range estimates the user can adjust per item.
///
/// Items come from the master [gearCatalog]: each entry carries strict
/// include/exclude rules (activity, carry mode, accommodation, season,
/// temperature gates, weather, dog/comfort flags). The engine derives
/// [TripConditions] from the trip, the forecast and the profile, then
/// keeps only catalog entries whose rules all match.
class PackingEngine {
  static const _uuid = Uuid();
  static String _id() => _uuid.v4().substring(0, 8);

  /// Derives the condition context the catalog is filtered against.
  TripConditions _conditions(Trip trip, UserProfile? profile) {
    var rain = false, heavyRain = false, cold = false, wind = false;
    var storm = false;
    double? minTemp;
    double? forecastEle;
    final now = DateTime.now();
    for (final s in trip.stages) {
      final (from, to) = TripAnalysis.stageWindow(s, trip);
      final fresh = TripAnalysis.snapshotsForStage(trip, s)
          .where((snapshot) => TripAnalysis.forecastIsFresh(snapshot, now))
          .toList();
      final c = TripAnalysis.summarize(fresh, from, to);
      if (c.rainExpected) rain = true;
      if (c.heavyRain) heavyRain = true;
      if (c.strongWind) wind = true;
      if (c.storm) storm = true;
      if (c.minTemp != null && (minTemp == null || c.minTemp! < minTemp)) {
        minTemp = c.minTemp;
      }
      for (final snapshot in fresh) {
        final ele = snapshot.elevation;
        if (ele != null && (forecastEle == null || ele > forecastEle)) {
          forecastEle = ele;
        }
      }
      final (nf, nt) = TripAnalysis.nightWindow(s, trip);
      final n = TripAnalysis.summarize(fresh, nf, nt);
      if (n.freezingTemps) cold = true;
      if (n.heavyRain) heavyRain = true;
      if (n.storm) storm = true;
      if (n.minTemp != null && (minTemp == null || n.minTemp! < minTemp)) {
        minTemp = n.minTemp;
      }
    }
    // MET was asked for the sample altitude. The summit can sit well
    // above that. 0.65 °C / 100 m is the standard lapse — an estimate,
    // applied only for the gap the forecast did not already cover.
    var minTempEstimated = false;
    final high = trip.route?.highestPoint;
    if (minTemp != null && high != null && forecastEle != null) {
      final extra = high - forecastEle;
      if (extra >= 100) {
        minTemp = minTemp! - 0.65 * (extra / 100);
        minTempEstimated = true;
      }
    }
    if (minTemp != null && minTemp! <= 0) cold = true;
    // Season is a stronger signal than a 9-day forecast: anything but
    // high summer means cold nights are plausible in the mountains.
    final winter = trip.season == TripSeason.winter;
    final shoulder =
        trip.season == TripSeason.spring || trip.season == TripSeason.autumn;
    if (winter || shoulder) cold = true;
    // Real snow on the ground (seNorge) counts like winter for
    // shelter and footwear, whatever the calendar says.
    final snowDepth = trip.maxSnowDepthCm;
    final snowOnGround = (snowDepth ?? 0) >= 20;

    // Avalanche gear follows terrain risk, not season alone. An
    // explicit user answer wins; fetched Varsom warnings always mean
    // possible terrain; unknown on a winter/ski trip is treated as
    // uncertain rather than "no risk".
    final avalanche =
        trip.avalancheWarnings.any((w) => w.dangerLevel > 0) ||
            trip.avalancheTerrain == true
        ? AvalancheRisk.yes
        : trip.avalancheTerrain == false
        ? AvalancheRisk.none
        // Prepared tracks are not avalanche terrain.
        : (trip.activity == TripActivity.ski && trip.skiStyle == SkiStyle.track)
        ? AvalancheRisk.none
        : (winter || trip.activity == TripActivity.ski)
        ? AvalancheRisk.uncertain
        : AvalancheRisk.none;

    return TripConditions(
      activity: trip.activity,
      carry: trip.carry,
      accommodation: trip.accommodation,
      cabinType: trip.cabinType,
      cabinNights: trip.cabinNights,
      season: trip.season,
      days: trip.hikingDays,
      people: trip.participants.clamp(1, 20),
      children: trip.children.clamp(0, 20),
      skiStyle: trip.skiStyle,
      snowshoes: trip.snowshoes,
      fishing: trip.fishing,
      maxSlopeDegrees:
          trip.route?.maxSlopeDegrees ??
          (trip.route == null
              ? null
              : steepestGradeDegrees(trip.route!.points)),
      minTemp: minTemp,
      minTempEstimated: minTempEstimated,
      rain: rain,
      heavyRain: heavyRain,
      strongWind: wind,
      storm: storm,
      snow: winter || snowOnGround,
      cold: cold || snowOnGround,
      snowDepthCm: snowDepth,
      // Short daylight outside summer makes a headlamp essential.
      darkEvenings: trip.hikingDays > 1 || shoulder || winter,
      avalanche: avalanche,
      withDog: trip.withDog ?? profile?.withDog ?? false,
      lightPacker: profile?.lightPacker ?? false,
      extraComfort: profile?.extraComfort ?? false,
      coldSensitive: profile?.coldSensitive ?? false,
      ownsTent: profile?.ownsTent ?? true,
      ownsStove: profile?.ownsStove ?? true,
    );
  }

  /// The exact conditions the catalog is filtered against. Exposed so
  /// the planning-context UI can show the same basis the rules used —
  /// one source of truth, never a parallel derivation.
  TripConditions conditionsFor(Trip trip, UserProfile? profile) =>
      _conditions(trip, profile);

  /// Generates a fresh packing list for [trip] by filtering the master
  /// [gearCatalog] against [TripConditions].
  /// [preservePacked] merges existing user state by catalog id, falling
  /// back to name for older lists with random ids.
  /// [pastTrips] feeds review-based learning: items the user marked as
  /// unnecessary/missing on earlier trips are annotated and adjusted —
  /// safety equipment is never removed automatically. [profile]
  /// sharpens the list with personal traits (e.g. cold-sensitive).
  List<PackingItem> generate(
    Trip trip, {
    bool preservePacked = true,
    List<Trip> pastTrips = const [],
    UserProfile? profile,
  }) {
    final ctx = _conditions(trip, profile);
    final items = <PackingItem>[
      for (final g in gearCatalog)
        // Tombstoned ids are skipped: the user explicitly removed the
        // suggestion, and that choice survives regeneration.
        if (!trip.deletedGearIds.contains(g.id) && g.matches(ctx))
          g.toItem(ctx),
    ];
    // Gramjeger: drop every generated "optional" item — the profile
    // explicitly asked for a minimalist list. Safety gear (required
    // or recommended) is never touched.
    if (ctx.lightPacker) {
      items.removeWhere((i) => i.priority == PackingPriority.optional);
    }
    // Unconfirmed avalanche terrain: the trio stays on the list but as
    // recommended, so prepared-trail ski days aren't flagged as unsafe.
    if (ctx.avalanche == AvalancheRisk.uncertain) {
      for (final i in items) {
        if (const {'beacon', 'shovel', 'probe'}.contains(i.id) &&
            i.priority == PackingPriority.required) {
          i.priority = PackingPriority.recommended;
        }
      }
    }

    // ── Learn from past reviews ─────────────────────────────
    _applyExperience(items, pastTrips);

    // ── Merge with existing list ────────────────────────────
    if (preservePacked && trip.packingList.isNotEmpty) {
      // Generated items now carry stable catalog ids — match on id
      // first, fall back to name for lists written before ids were
      // stable (their items still get their state merged).
      final byId = <String, PackingItem>{};
      final byName = <String, PackingItem>{};
      for (final i in trip.packingList) {
        byId[i.id] = i;
        byName[i.name.toLowerCase()] = i;
      }
      for (final item in items) {
        final existing = byId[item.id] ?? byName[item.name.toLowerCase()];
        if (existing != null) {
          // Only explicit overrides survive; otherwise regenerated
          // quantity/priority continue to follow the new trip conditions.
          item.packed = existing.packed;
          item.worn = existing.worn;
          item.consumable = existing.consumable;
          item.needsAcquisition = existing.needsAcquisition;
          item.unitWeightGrams = existing.unitWeightGrams;
          item.nameEdited =
              existing.nameEdited ||
              (item.id == existing.id && existing.name != item.name);
          item.quantityEdited = existing.quantityEdited;
          item.priorityEdited = existing.priorityEdited;
          item.weightEdited = existing.weightEdited;
          if (item.nameEdited) item.name = existing.name;
          if (item.quantityEdited) item.quantity = existing.quantity;
          if (item.priorityEdited) item.priority = existing.priority;
        }
      }
      // Keep user-added items.
      for (final existing in trip.packingList) {
        if (existing.userAdded &&
            !items.any(
              (i) => i.name.toLowerCase() == existing.name.toLowerCase(),
            )) {
          items.add(existing);
        }
      }
    }
    return items;
  }

  PackingItem _item(
    String name,
    PackingCategory cat, {
    double qty = 1,
    double grams = 0,
    PackingPriority priority = PackingPriority.recommended,
    bool worn = false,
    String? reason,
  }) => PackingItem(
    id: _id(),
    name: name,
    category: cat,
    quantity: qty,
    unitWeightGrams: grams,
    priority: priority,
    worn: worn,
    reason: reason,
    needsAcquisition: reason?.contains('må lånes') ?? false,
  );

  /// Normalizes a name for loose matching (lowercase, letters/digits).
  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-zæøå0-9]+'), ' ').trim();

  /// True when the learned name plausibly refers to the item — either
  /// name containing the other's full text, or sharing a long token.
  static bool _sameItem(String learned, String itemName) {
    final l = _key(learned), i = _key(itemName);
    if (l.isEmpty || i.isEmpty) return false;
    if (i.contains(l) || l.contains(i)) return true;
    for (final tok in l.split(' ')) {
      if (tok.length >= 4 && i.contains(tok)) return true;
    }
    return false;
  }

  /// Applies review feedback from earlier trips to the generated list:
  /// - «missing» entries boost priority / are added if absent
  /// - «unnecessary» entries annotate and demote non-required items
  /// - «workedWell» entries get a positive annotation
  /// Required (safety) items are never removed or demoted.
  void _applyExperience(List<PackingItem> items, List<Trip> pastTrips) {
    final missing = <String, String>{}; // name -> trip name
    final unnecessary = <String, String>{};
    final worked = <String>{};
    for (final t in pastTrips) {
      final r = t.review;
      if (r == null) continue;
      final label = t.name.isEmpty ? 'tidligere tur' : '«${t.name}»';
      for (final n in r.missing) {
        missing.putIfAbsent(n, () => label);
      }
      for (final n in r.unnecessary) {
        unnecessary.putIfAbsent(n, () => label);
      }
      worked.addAll(r.workedWell);
    }
    if (missing.isEmpty && unnecessary.isEmpty && worked.isEmpty) return;

    final learnedMissing = missing.entries.toList();
    for (final item in items) {
      final src = missing.entries
          .where((e) => _sameItem(e.key, item.name))
          .firstOrNull;
      if (src != null) {
        learnedMissing.remove(src);
        item.reason =
            '${item.reason != null ? '${item.reason} · ' : ''}'
            'Manglet på ${src.value} – inkludert igjen';
        if (item.priority == PackingPriority.optional) {
          item.priority = PackingPriority.recommended;
        }
      }
      final un = unnecessary.entries
          .where((e) => _sameItem(e.key, item.name))
          .firstOrNull;
      if (un != null) {
        item.reason =
            '${item.reason != null ? '${item.reason} · ' : ''}'
            'Merket unødvendig på ${un.value}'
            '${item.priority == PackingPriority.required ? ' – beholdes likevel for sikkerhet' : ''}';
        if (item.priority == PackingPriority.recommended) {
          item.priority = PackingPriority.optional;
        }
      }
      if (worked.any((w) => _sameItem(w, item.name))) {
        item.reason =
            '${item.reason != null ? '${item.reason} · ' : ''}'
            'Fungerte bra på tidligere tur';
      }
    }
    // Missing items with no counterpart on the list are added.
    for (final e in learnedMissing) {
      items.add(
        _item(
          e.key,
          PackingCategory.additional,
          priority: PackingPriority.recommended,
          reason: 'Manglet på ${e.value}',
        ),
      );
    }
  }

  /// Describes what "Optimize" would change so the user can confirm.
  List<String> describeOptimization(Trip trip) {
    final notes = <String>[];
    final items = trip.packingList;
    final optionalPacked = items
        .where((i) => i.priority == PackingPriority.optional && i.packed)
        .toList();
    if (optionalPacked.isNotEmpty) {
      notes.add(
        'Fjerner ${optionalPacked.length} valgfri(e) gjenstand(er) som ikke er pakket uansett? Nei – beholdes, men du bør vurdere dem.',
      );
    }
    final dupes = <String>[];
    final seen = <String>{};
    for (final i in items) {
      final k = i.name.toLowerCase();
      if (!seen.add(k)) dupes.add(i.name);
    }
    if (dupes.isNotEmpty) {
      notes.add(
        'Slår sammen ${dupes.length} duplikat(er): ${dupes.join(', ')}',
      );
    }
    final noWeight = items.where((i) => i.unitWeightGrams == 0).length;
    if (noWeight > 0) {
      notes.add('$noWeight gjenstand(er) mangler vekt – estimeres ikke.');
    }
    if (notes.isEmpty) {
      notes.add('Listen er allerede ryddig. Ingen endringer foreslås.');
    }
    notes.add(
      'Sikkerhetsutstyr (førstehjelp, vindsekk, kart/kompass) fjernes aldri automatisk.',
    );
    return notes;
  }

  /// Applies safe optimizations: merges duplicates only. Never removes
  /// safety-critical items.
  int optimize(Trip trip) {
    final seen = <String, PackingItem>{};
    var removed = 0;
    trip.packingList = trip.packingList.where((i) {
      final k = i.name.toLowerCase();
      if (seen.containsKey(k) && seen[k]!.priority == i.priority) {
        seen[k]!.quantity += i.quantity;
        seen[k]!.packed = seen[k]!.packed || i.packed;
        removed++;
        return false;
      }
      seen[k] = i;
      return true;
    }).toList();
    return removed;
  }
}
