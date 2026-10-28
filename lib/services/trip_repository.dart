import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/catalog_trip.dart';
import '../models/packing.dart';
import '../models/profile.dart';
import '../models/trip.dart';
import 'tile_cache.dart';
import 'trip_cloud_store.dart';

/// Persistence: local Hive storage is the primary store (works
/// offline) and trips are mirrored to Firestore under
/// users/{uid}/trips/{id} when the user is signed in. Cloud failures
/// never break local saves.
class TripRepository {
  static const _tripsBox = 'trips';
  static const _settingsBox = 'settings';
  static const _templatesKey = 'packing_templates';
  static const _profileKey = 'user_profile';

  final String? storagePath;
  TripCloudStore? _tripCloud;
  TripRepository({this.storagePath, TripCloudStore? cloudStore})
    : _tripCloud = cloudStore;

  Box<String>? _trips;
  Box<dynamic>? _settings;
  Box<dynamic>? _profileSettings;
  Box<String>? _pending;
  Box<String>? _conflicts;
  FirebaseFirestore? _db;
  String? _uid;
  bool _initialized = false;
  int _generation = 0;
  final _owners = Expando<String>();
  Future<void> _syncTail = Future.value();
  final syncStatus = ValueNotifier<TripSyncStatus>(const TripSyncStatus());
  String get _scopeKey => _uid == null ? 'guest' : 'user:$_uid';
  int get pendingCount => _pending?.length ?? 0;

  void _status(String scope, TripSyncPhase phase, {String? message}) {
    if (scope == _scopeKey) {
      syncStatus.value = TripSyncStatus(
        phase: phase,
        pendingCount: pendingCount,
        message: message,
      );
    }
  }

  Future<T> _serialize<T>(Future<T> Function() work) {
    final result = _syncTail.then((_) => work());
    _syncTail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Set the signed-in user id for cloud sync (null = signed out).
  Future<void> setUser(String? uid) async {
    if (_uid == uid && _trips != null) return;
    final generation = ++_generation;
    _uid = uid;
    _trips = null;
    _profileSettings = null;
    _pending = null;
    _conflicts = null;
    cloudConflictIds.clear();
    _status(_scopeKey, TripSyncPhase.localOnly);
    if (!_initialized) return;
    final suffix = uid == null
        ? 'guest'
        : utf8
              .encode(uid)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
    final trips = await Hive.openBox<String>(
      uid == null ? _tripsBox : 'trips_user_$suffix',
    );
    final pending = await Hive.openBox<String>('trip_pending_$suffix');
    final conflicts = await Hive.openBox<String>('trip_conflicts_$suffix');
    final settings = uid == null
        ? _settings!
        : await Hive.openBox<dynamic>('profile_user_$suffix');
    if (generation != _generation) return;
    for (final id in pending.keys.cast<String>().toList()) {
      final record = CloudTripRecord.fromJson(
        jsonDecode(pending.get(id)!) as Map<String, dynamic>,
      );
      if (record.deleted) {
        await trips.delete(id);
      } else if (record.data != null && !trips.containsKey(id)) {
        // The pending document is an upload queue, not a replacement for
        // the richer local copy (v2 omits GPS tracks and fetched data).
        // Only recover from it when the local record is actually missing.
        final trip = Trip.decodeAny(record.data!);
        if (trip.id != id) throw const FormatException('Ugyldig lokal tur-id.');
        await trips.put(id, trip.encode());
      }
    }
    if (generation != _generation) return;
    _trips = trips;
    _pending = pending;
    _conflicts = conflicts;
    _profileSettings = settings;
    cloudConflictIds.addAll(conflicts.keys.cast<String>());
    _status(
      _scopeKey,
      uid == null ? TripSyncPhase.localOnly : TripSyncPhase.pending,
    );
  }

  Future<void> init() async {
    if (storagePath case final path?) {
      Hive.init(path);
    } else {
      await Hive.initFlutter('norgeskompasset');
    }
    _settings = await Hive.openBox<dynamic>(_settingsBox);
    _initialized = true;
    await setUser(null);
    await TileCache.init();
    try {
      _db = FirebaseFirestore.instance;
      _tripCloud ??= FirestoreTripCloudStore(_db!);
    } catch (_) {
      // Firebase not configured — local storage still works.
    }
  }

  List<Trip> loadTrips() {
    final box = _trips;
    if (box == null) return [];
    final out = <Trip>[];
    for (final key in box.keys) {
      try {
        final trip = Trip.decode(box.get(key)!);
        _owners[trip] = _scopeKey;
        out.add(trip);
      } catch (_) {
        // Skip corrupt entries rather than crash.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// Saves the trip locally (awaited) and mirrors it to Firestore.
  /// The cloud write is fire-and-forget so saves never block the UI on
  /// network latency; [syncCloud] lets high-frequency callers (track
  /// recording) skip the push and batch it less often.
  Future<void> saveTrip(Trip trip, {bool syncCloud = true}) async {
    final scope = _scopeKey;
    if (_owners[trip] != null && _owners[trip] != scope) {
      throw StateError('Turen tilhører en annen lokal bruker.');
    }
    _owners[trip] = scope;
    final trips = _trips;
    final pending = _pending;
    final conflicts = _conflicts;
    final uid = _uid;
    trip.updatedAt = DateTime.now();
    final encoded = trip.encode();
    // Cloud documents use the compact v2 snapshot: trip choices, the
    // route and user state — no derived stages, forecast payloads,
    // warnings or track log (all rebuilt/refetched on the device).
    final operation = CloudTripRecord(
      data: jsonEncode(trip.toSyncJson()),
      updatedAt: trip.updatedAt,
    );
    if (uid != null) {
      await pending?.put(trip.id, jsonEncode(operation.toJson()));
    }
    await trips?.put(trip.id, encoded);
    _status(
      scope,
      uid == null ? TripSyncPhase.localOnly : TripSyncPhase.pending,
    );
    if (syncCloud && uid != null && pending != null && conflicts != null) {
      unawaited(_pushToCloud(uid, scope, pending, conflicts));
    }
  }

  Future<void> _pushToCloud(
    String uid,
    String scope,
    Box<String> pending,
    Box<String> conflicts,
  ) async {
    try {
      await _serialize(() => _flush(uid, scope, pending, conflicts));
    } catch (_) {
      // Offline or missing permissions — local copy is intact.
      _status(
        scope,
        TripSyncPhase.error,
        message:
            'Skyoppdatering feilet. Endringene ligger i lokal kø. Prøv igjen.',
      );
    }
  }

  Future<void> _flush(
    String uid,
    String scope,
    Box<String> pending,
    Box<String> conflicts,
  ) async {
    final cloud = _tripCloud;
    if (cloud == null) throw StateError('Skytjenesten er ikke tilgjengelig.');
    _status(scope, TripSyncPhase.syncing);
    for (final id in pending.keys.cast<String>().toList()) {
      if (scope != _scopeKey) return;
      final raw = pending.get(id);
      if (raw == null) continue;
      final record = CloudTripRecord.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final applied = await cloud
          .apply(uid, id, record)
          .timeout(const Duration(seconds: 20));
      if (applied) {
        if (pending.get(id) == raw) await pending.delete(id);
      } else {
        await conflicts.put(id, raw);
        if (scope == _scopeKey) cloudConflictIds.add(id);
      }
    }
    _status(
      scope,
      conflicts.isNotEmpty
          ? TripSyncPhase.conflict
          : pending.isEmpty
          ? TripSyncPhase.synced
          : TripSyncPhase.pending,
    );
  }

  Future<void> deleteTrip(String id) async {
    final scope = _scopeKey;
    final trips = _trips;
    final pending = _pending;
    final conflicts = _conflicts;
    final uid = _uid;
    if (uid != null) {
      await pending?.put(
        id,
        jsonEncode(
          CloudTripRecord(updatedAt: DateTime.now(), deleted: true).toJson(),
        ),
      );
    }
    await trips?.delete(id);
    await conflicts?.delete(id);
    if (scope == _scopeKey) cloudConflictIds.remove(id);
    if (uid != null && pending != null && conflicts != null) {
      unawaited(_pushToCloud(uid, scope, pending, conflicts));
    }
  }

  /// Trip ids where the cloud copy was newer than the local one and
  /// overwrote it — i.e. the trip was edited on another device since
  /// this device last synced. Surfaced in the UI so the overwrite
  /// isn't silent. Cleared when the user acknowledges via [clearConflict].
  final Set<String> cloudConflictIds = {};

  /// Acknowledges a conflict and keeps the version shown on this device.
  /// A local edit still queued behind a newer cloud copy is re-stamped so
  /// it wins the next upload instead of staying stuck in the queue.
  Future<void> clearConflict(String id) async {
    final scope = _scopeKey;
    final trips = _trips;
    final pending = _pending;
    final conflicts = _conflicts;
    cloudConflictIds.remove(id);
    await conflicts?.delete(id);
    final raw = trips?.get(id);
    if (pending != null && pending.containsKey(id) && raw != null) {
      await saveTrip(Trip.decode(raw));
    } else if (conflicts != null &&
        conflicts.isEmpty &&
        syncStatus.value.phase == TripSyncPhase.conflict) {
      _status(
        scope,
        pendingCount == 0 ? TripSyncPhase.synced : TripSyncPhase.pending,
      );
    }
  }

  /// Merges the user's cloud trips into local storage (newest
  /// updatedAt wins) and pushes local trips the cloud is missing.
  /// Returns the number of trips imported; ids of local copies that
  /// were overwritten by a newer cloud version land in
  /// [cloudConflictIds].
  Future<int> syncFromCloud() async {
    final uid = _uid;
    final scope = _scopeKey;
    final trips = _trips;
    final pending = _pending;
    final conflicts = _conflicts;
    final cloud = _tripCloud;
    if (uid == null) return 0;
    if (cloud == null ||
        trips == null ||
        pending == null ||
        conflicts == null) {
      throw StateError('Skytjenesten er ikke klar.');
    }
    try {
      return await _serialize(() async {
        _status(scope, TripSyncPhase.syncing);
        final remote = await cloud
            .readTrips(uid)
            .timeout(const Duration(seconds: 20));
        var imported = 0;
        for (final entry in remote.entries) {
          if (scope != _scopeKey) return imported;
          final id = entry.key;
          final record = entry.value;
          if (pending.containsKey(id)) continue;
          final raw = trips.get(id);
          final local = raw == null ? null : Trip.decode(raw);
          if (local != null && local.updatedAt.isAfter(record.updatedAt)) {
            await pending.put(
              id,
              jsonEncode(
                CloudTripRecord(
                  data: jsonEncode(local.toSyncJson()),
                  updatedAt: local.updatedAt,
                ).toJson(),
              ),
            );
          } else if (record.deleted) {
            await trips.delete(id);
          } else if (local == null ||
              record.updatedAt.isAfter(local.updatedAt)) {
            // Cloud docs may be v2 snapshots or legacy full JSON.
            final incoming = Trip.decodeAny(record.data!);
            if (incoming.id != id) {
              throw const FormatException('Ugyldig tur-id fra skyen.');
            }
            // v2 deliberately omits the device's GPS log. A newer
            // plan from another device must not erase that local log.
            if (local != null &&
                (jsonDecode(record.data!) as Map<String, dynamic>)['v'] ==
                    Trip.syncVersion) {
              incoming.trackLog = local.trackLog;
            }
            if (raw != null) {
              await conflicts.put(id, raw);
              cloudConflictIds.add(id);
            }
            await trips.put(id, incoming.encode());
            if (local == null) imported++;
          }
        }
        // Push local trips the cloud doesn't have yet.
        for (final id in trips.keys.cast<String>().toList()) {
          if (scope != _scopeKey) return imported;
          if (remote.containsKey(id) || pending.containsKey(id)) continue;
          final raw = trips.get(id)!;
          final localTrip = Trip.decode(raw);
          await pending.put(
            id,
            jsonEncode(
              CloudTripRecord(
                data: jsonEncode(localTrip.toSyncJson()),
                updatedAt: localTrip.updatedAt,
              ).toJson(),
            ),
          );
        }
        await _flush(uid, scope, pending, conflicts);
        return imported;
      });
    } catch (_) {
      _status(
        scope,
        TripSyncPhase.error,
        message: 'Kunne ikke synkronisere. Lokale data og kø er bevart.',
      );
      rethrow;
    }
  }

  // ── Shared trips ───────────────────────────────────────────
  /// Shared-trip documents live at sharedTrips/{code} — readable by
  /// any signed-in user who knows the code, writable by the owner.
  CollectionReference<Map<String, dynamic>>? get _shared =>
      _db?.collection('sharedTrips');

  /// Publishes a snapshot of [trip] under a short share code and
  /// returns the code. The published copy is the shared *plan* —
  /// personal data (GPS track log, review) is stripped before upload.
  /// Returns null when signed out/offline.
  Future<String?> publishTrip(Trip trip) async {
    final shared = _shared;
    if (shared == null || _uid == null) return null;
    final code = trip.shareCode ?? _newShareCode();
    final j = trip.toJson()
      ..['trackLog'] = <dynamic>[]
      ..['review'] = null;
    try {
      // Serialize with trip sync so Firestore's native desktop plugin never
      // sees two overlapping writes from this repository.
      await _serialize(
        () => shared.doc(code).set({
          'data': jsonEncode(j),
          'name': trip.name,
          'owner': _uid,
          'updatedAt': trip.updatedAt.toIso8601String(),
        }),
      );
      trip.shareCode = code;
      return code;
    } catch (_) {
      return null;
    }
  }

  /// Stops sharing [trip] by deleting its shared snapshot so the code no
  /// longer works. Returns true when removed (or already gone), false
  /// when the snapshot belongs to someone else, null on failure.
  Future<bool?> unpublishTrip(Trip trip) async {
    final shared = _shared;
    final uid = _uid;
    final code = trip.shareCode;
    if (shared == null || uid == null || code == null) return null;
    try {
      final removed = await _serialize(() async {
        final doc = shared.doc(code);
        final snapshot = await doc.get();
        if (!snapshot.exists) return true;
        if (snapshot.data()?['owner'] != uid) return false;
        await doc.delete();
        return true;
      });
      if (removed) trip.shareCode = null;
      return removed;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the trip snapshot published under [code]. Returns null
  /// when the code doesn't exist or the fetch fails.
  Future<Trip?> fetchSharedTrip(String code) async {
    final shared = _shared;
    if (shared == null) return null;
    try {
      final doc = await _serialize(
        () => shared.doc(code.trim().toUpperCase()).get(),
      );
      final raw = doc.data()?['data'] as String?;
      if (raw == null) return null;
      final trip = Trip.decode(raw);
      trip.shareCode = doc.id;
      return trip;
    } catch (_) {
      return null;
    }
  }

  // ── Tour catalog ───────────────────────────────────────────
  /// Curated/user-published tours at catalogTrips/{id} — readable by
  /// any signed-in user, writable by the publishing owner.
  CollectionReference<Map<String, dynamic>>? get _catalog =>
      _db?.collection('catalogTrips');

  /// Publishes [trip]'s route as a catalog entry and returns the doc
  /// id (null on failure). Re-publishing the same entry id updates it.
  Future<String?> publishToCatalog(CatalogTrip entry) async {
    final catalog = _catalog;
    if (catalog == null || _uid == null) return null;
    try {
      final doc = entry.id.isEmpty ? catalog.doc() : catalog.doc(entry.id);
      entry.id = doc.id;
      entry.ownerUid = _uid!;
      await _serialize(() => doc.set(entry.toJson()));
      return doc.id;
    } catch (_) {
      return null;
    }
  }

  /// Fetches every catalog entry (sorted newest first). Returns an
  /// empty list on failure/offline.
  Future<List<CatalogTrip>> fetchCatalog({bool includeHidden = false}) async {
    final catalog = _catalog;
    if (catalog == null) return const [];
    try {
      final snap = await _serialize(() => catalog.get());
      return [
        for (final d in snap.docs)
          if (CatalogTrip.fromJson(d.data()) case final e)
            if (includeHidden ||
                e.reportedBy.length < CatalogTrip.reportHideThreshold)
              e,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Adds the signed-in user's report to a catalog entry. Entries
  /// reaching [CatalogTrip.reportHideThreshold] reports are hidden
  /// from listings until reviewed.
  Future<bool> reportCatalogEntry(String id) async {
    final doc = _catalog?.doc(id);
    final uid = _uid;
    if (doc == null || uid == null) return false;
    try {
      await _serialize(
        () => doc.update({
          'reportedBy': FieldValue.arrayUnion([uid]),
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin review: clears the reports so the entry is visible again.
  /// The Firestore rules only allow this for uids in config/admins.
  Future<bool> clearCatalogReports(String id) async {
    final doc = _catalog?.doc(id);
    if (doc == null) return false;
    try {
      await _serialize(() => doc.update({'reportedBy': <String>[]}));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCatalogEntry(String id) async {
    try {
      final doc = _catalog?.doc(id);
      if (doc == null) return false;
      await _serialize(() => doc.delete());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin uids live in config/admins {uids: [...]} — maintained in the
  /// Firebase console and enforced by the Firestore rules, never by the
  /// app alone.
  Future<bool> fetchIsAdmin() async {
    final uid = _uid;
    final db = _db;
    if (uid == null || db == null) return false;
    try {
      final snap = await _serialize(() => db.doc('config/admins').get());
      final uids = snap.data()?['uids'];
      return uids is List && uids.contains(uid);
    } catch (_) {
      return false;
    }
  }

  // ── Account deletion ───────────────────────────────────────
  /// Deletes every cloud document owned by the signed-in user:
  /// users/{uid}/trips/*, the user doc itself, the user's shared
  /// snapshots and catalog entries. Throws on failure so the caller
  /// can abort before the auth account is removed — otherwise data
  /// would be orphaned under a uid nobody can log in to.
  Future<void> deleteAllCloudData() async {
    final db = _db;
    final uid = _uid;
    if (db == null || uid == null) return;
    final userDoc = db.collection('users').doc(uid);
    final trips = await userDoc.collection('trips').get();
    for (final doc in trips.docs) {
      await doc.reference.delete();
    }
    await userDoc.delete();
    // The sharedTrips rules allow get-by-id only, not listing — so
    // delete the share codes this device knows (they sync with the
    // trip data). Verify ownership before deleting.
    for (final trip in loadTrips()) {
      final code = trip.shareCode;
      if (code == null) continue;
      final ref = db.collection('sharedTrips').doc(code);
      final doc = await ref.get();
      if (doc.exists && doc.data()?['owner'] == uid) await ref.delete();
    }
    // Catalog entries are listable for signed-in users.
    final owned = await db
        .collection('catalogTrips')
        .where('owner', isEqualTo: uid)
        .get();
    for (final doc in owned.docs) {
      await doc.reference.delete();
    }
  }

  /// Copies this user's local trips and profile into the guest store so
  /// they keep working offline after the account is deleted.
  Future<void> migrateLocalDataToGuest() async {
    final trips = loadTrips();
    final profile = loadProfile();
    final guestTrips = await Hive.openBox<String>(_tripsBox);
    await guestTrips.clear();
    for (final t in trips) {
      await guestTrips.put(t.id, t.encode());
    }
    await _settings?.put(_profileKey, profile.encode());
  }

  /// Wipes this user's local trips, sync queue, conflicts and profile.
  /// Used when the user asks to delete everything.
  Future<void> clearLocalUserData() async {
    await _trips?.clear();
    await _pending?.clear();
    await _conflicts?.clear();
    await _profileSettings?.clear();
    cloudConflictIds.clear();
  }

  static const _codeChars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  String _newShareCode() {
    final rnd = Random.secure();
    return List.generate(
      6,
      (_) => _codeChars[rnd.nextInt(_codeChars.length)],
    ).join();
  }

  // ── App preferences ────────────────────────────────────────
  /// Stored theme preference: 'system' | 'light' | 'dark'.
  UserProfile loadProfile() {
    final raw = _profileSettings?.get(_profileKey) as String?;
    if (raw == null || raw.isEmpty) return UserProfile();
    try {
      return UserProfile.decode(raw);
    } catch (_) {
      return UserProfile();
    }
  }

  Future<void> saveProfile(UserProfile profile) =>
      _profileSettings?.put(_profileKey, profile.encode()) ?? Future.value();

  /// Stored theme preference: 'system' | 'light' | 'dark'.
  String get themeModePref =>
      _settings?.get('theme_mode') as String? ?? 'system';

  Future<void> saveThemeModePref(String mode) =>
      _settings?.put('theme_mode', mode) ?? Future.value();

  /// Whether the first-run onboarding cards have been shown.
  bool get onboardingSeen =>
      _settings?.get('onboarding_seen') as bool? ?? false;

  Future<void> saveOnboardingSeen() =>
      _settings?.put('onboarding_seen', true) ?? Future.value();

  /// Whether the user chose «Fortsett lokalt uten konto» - remembered
  /// so the login screen is not shown again on every start.
  bool get localModePref => _settings?.get('local_mode') as bool? ?? false;

  Future<void> saveLocalModePref(bool value) =>
      _settings?.put('local_mode', value) ?? Future.value();

  // ── Tour calendar cache (so the list shows offline) ────────
  static const _eventsKey = 'events_cache';

  ({List<Map<String, dynamic>> events, DateTime? fetchedAt}) cachedEvents() {
    final raw = _settings?.get(_eventsKey);
    if (raw is! Map) return (events: const [], fetchedAt: null);
    final list = raw['events'];
    return (
      events: [
        if (list is List)
          for (final e in list)
            if (e is Map) Map<String, dynamic>.from(e),
      ],
      fetchedAt: DateTime.tryParse(raw['fetchedAt'] as String? ?? ''),
    );
  }

  Future<void> cacheEvents(List<Map<String, dynamic>> events) =>
      _settings?.put(_eventsKey, {
        'events': events,
        'fetchedAt': DateTime.now().toIso8601String(),
      }) ??
      Future.value();

  // ── Packing templates ──────────────────────────────────────
  List<Map<String, dynamic>> loadTemplates() {
    final raw = _profileSettings?.get(_templatesKey) as List? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> saveTemplate(String name, List<PackingItem> items) async {
    final templates = loadTemplates();
    templates.removeWhere((t) => t['name'] == name);
    templates.add({
      'name': name,
      'items': items.map((i) => i.toJson()).toList(),
      'savedAt': DateTime.now().toIso8601String(),
    });
    await _profileSettings?.put(_templatesKey, templates);
  }

  Future<void> deleteTemplate(String name) async {
    final templates = loadTemplates();
    templates.removeWhere((t) => t['name'] == name);
    await _profileSettings?.put(_templatesKey, templates);
  }
}
