import 'dart:async';

import 'package:flutter/material.dart'
    show ThemeMode, WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/energy.dart';
import '../core/format.dart';
import '../core/geo.dart';
import '../models/alert.dart';
import '../models/calendar_event.dart';
import '../models/catalog_trip.dart';
import '../models/packing.dart';
import '../models/food_menu.dart';
import '../models/profile.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/track.dart';
import '../models/trip.dart';
import '../services/auth_service.dart';
import '../services/elevation_service.dart';
import '../services/geocoding_service.dart';
import '../services/gear_catalog.dart';
import '../services/meal_planner.dart';
import '../services/packing_change.dart';
import '../services/packing_engine.dart';
import '../services/recommendation_engine.dart';
import '../services/routing_service.dart';
import '../services/stage_builder.dart';
import '../services/tile_cache.dart';
import '../services/events_service.dart';
import '../services/trip_repository.dart';
import '../services/tracking_controller.dart';
import '../services/turrutebase_service.dart';
import '../services/varsom_service.dart';
import '../services/weather_service.dart';

/// Central application state. All trip-related screens operate on the
/// same [currentTrip] record; every mutation persists via [TripRepository].
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final TripRepository repo;
  final weatherService = WeatherService();
  final elevationService = ElevationService();
  final routingService = RoutingService();
  final geocodingService = GeocodingService();
  final varsomService = VarsomService();
  final packingEngine = PackingEngine();
  final recommendationEngine = RecommendationEngine();

  List<Trip> trips = [];
  String? currentTripId;
  bool busy = false;
  String? busyLabel;

  /// Personal profile — sharpens packing lists and meal plans, and
  /// supplies contact/medical info on the shared safety card.
  UserProfile profile = UserProfile();
  String? lastError;
  bool localOnly = false;

  /// Latest forecast-driven packing change per trip id, until dismissed.
  final packingChanges = <String, PackingChange>{};

  void dismissPackingChange(String tripId) {
    if (packingChanges.remove(tripId) != null) notifyListeners();
  }

  Future<void> useLocalMode(bool value) async {
    if (value) await syncWithCloud(null);
    localOnly = value;
    await repo.saveLocalModePref(value);
    notifyListeners();
  }

  /// Deletes the signed-in account and all of its cloud data
  /// (Play Store/App Store requirement). [keepLocalTrips] controls
  /// whether the trips on this device are moved to the local,
  /// account-free store or wiped with everything else.
  ///
  /// Cloud cleanup runs first — if it throws, the auth account is
  /// left untouched so nothing is orphaned. Firebase may answer
  /// 'requires-recent-login'; reauthenticate via [AuthService] and
  /// call this again.
  Future<void> deleteAccount({required bool keepLocalTrips}) async {
    await repo.deleteAllCloudData();
    if (keepLocalTrips) {
      await repo.migrateLocalDataToGuest();
    } else {
      await repo.clearLocalUserData();
    }
    await AuthService().deleteAccount();
    // The account is gone — local mode must not suppress the login
    // screen, and the trips in memory belong to the deleted user.
    localOnly = false;
    await repo.saveLocalModePref(false);
    trips = [];
    currentTripId = null;
    profile = UserProfile();
    catalog = const [];
    catalogLoaded = false;
    notifyListeners();
  }

  late final TrackingController tracking;
  final trackRevision = ValueNotifier<int>(0);
  bool _observingLifecycle = false;

  AppState(this.repo, {TrackingLocationSource? trackingSource}) {
    tracking = TrackingController(
      source: trackingSource ?? GeolocatorTrackingSource(),
      onPosition: _recordPosition,
      onFlush: _flushTrackedTrip,
      routeProvider: () {
        final trip = trips.where((t) => t.id == tracking.tripId).firstOrNull;
        final route = trip?.route;
        // Only real trail geometry may raise deviation alerts —
        // estimated or imported routes are not verified corridors.
        return route != null && route.supportsDeviationAlerts
            ? route.points
            : null;
      },
      onOffRouteAlert: (_) => unawaited(HapticFeedback.vibrate()),
    );
  }

  Future<void> _recordPosition(String tripId, Position pos) async {
    final trip = trips.where((t) => t.id == tripId).firstOrNull;
    if (trip == null) return;
    final here = LatLng(pos.latitude, pos.longitude);
    // Record: new point when ≥10 m moved or ≥30 s since last fix.
    final last = trip.trackLog.isEmpty ? null : trip.trackLog.last;
    final moved =
        last == null ||
        metersBetween(LatLng(last.lat, last.lon), here) >= 10 ||
        pos.timestamp.difference(last.time).inSeconds >= 30;
    if (moved) {
      await recordTrackPoint(
        trip,
        TrackPoint(pos.latitude, pos.longitude, pos.altitude, pos.timestamp),
      );
    }
  }

  Future<void> _flushTrackedTrip(String id) async {
    final trip = trips.where((t) => t.id == id).firstOrNull;
    if (trip != null) await saveTrackNow(trip);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(tracking.flush().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    tracking.dispose();
    trackRevision.dispose();
    super.dispose();
  }

  Trip? get currentTrip {
    for (final t in trips) {
      if (t.id == currentTripId) return t;
    }
    return null;
  }

  Trip? get nextTrip {
    final upcoming =
        trips
            .where(
              (t) =>
                  t.status != TripStatus.completed &&
                  (t.startDate == null ||
                      !t.startDate!.isBefore(
                        DateTime.now().subtract(const Duration(days: 1)),
                      )),
            )
            .toList()
          ..sort(
            (a, b) => (a.startDate ?? DateTime(9999)).compareTo(
              b.startDate ?? DateTime(9999),
            ),
          );
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Future<void> init() async {
    await repo.init();
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
    _loadThemeMode();
    profile = repo.loadProfile();
    trips = repo.loadTrips();
    if (trips.isNotEmpty) currentTripId = trips.first.id;
    if (repo.localModePref) {
      await syncWithCloud(null);
      localOnly = true;
    }
    notifyListeners();
  }

  // ── Cloud sync ─────────────────────────────────────────────

  String? _syncedUid;
  bool _cloudSyncing = false;
  bool _accountReady = false;
  int _accountGeneration = 0;
  bool get cloudSyncing => _cloudSyncing;
  DateTime? lastCloudRefresh;
  String? cloudRefreshError;

  /// Ids of local trips overwritten by a newer cloud copy during
  /// sync — the trip was edited on another device. Surfaced in the
  /// UI so overwrites aren't silent.
  Set<String> get cloudConflicts => repo.cloudConflictIds;

  Future<void> clearCloudConflict(String tripId) async {
    await repo.clearConflict(tripId);
    notifyListeners();
  }

  /// Attach cloud sync to a signed-in user. Merges cloud trips into
  /// local storage once per user — later saves write through
  /// automatically via [TripRepository.saveTrip].
  Future<void> syncWithCloud(String? uid) async {
    if (_accountReady && _syncedUid == uid) return;
    final generation = ++_accountGeneration;
    _accountReady = false;
    await Future<void>.delayed(Duration.zero, tracking.stop);
    if (generation != _accountGeneration) return;
    if (tracking.phase == TrackingPhase.error) {
      throw StateError('Kunne ikke lagre sporet før kontobytte.');
    }
    _syncedUid = uid;
    _cloudSyncing = false;
    cloudRefreshError = null;
    lastCloudRefresh = null;
    trips = [];
    currentTripId = null;
    profile = UserProfile();
    catalog = const [];
    catalogLoaded = false;
    await repo.setUser(uid);
    if (generation != _accountGeneration) return;
    trips = repo.loadTrips();
    profile = repo.loadProfile();
    currentTripId = trips.firstOrNull?.id;
    _accountReady = true;
    notifyListeners();
    if (uid != null) unawaited(Future<void>.delayed(Duration.zero, syncNow));
  }

  /// Manually re-pulls cloud state — returns conflicted trip names.
  Future<void> syncNow() async {
    if (_syncedUid == null || _cloudSyncing || !_accountReady) return;
    final generation = _accountGeneration;
    _cloudSyncing = true;
    cloudRefreshError = null;
    notifyListeners();
    try {
      await tracking.flush();
      if (generation != _accountGeneration) return;
      final trackedTrip = trips
          .where((t) => t.id == tracking.tripId)
          .firstOrNull;
      await repo.syncFromCloud();
      if (generation != _accountGeneration) return;
      trips = repo.loadTrips();
      if (trackedTrip != null && trackedTrip.id == tracking.tripId) {
        trips.removeWhere((t) => t.id == trackedTrip.id);
        trips.insert(0, trackedTrip);
      }
      if (!trips.any((t) => t.id == currentTripId)) {
        currentTripId = trips.firstOrNull?.id;
      }
      lastCloudRefresh = DateTime.now();
    } catch (_) {
      if (generation == _accountGeneration) {
        cloudRefreshError = 'Kunne ikke oppdatere fra skyen. Lokale turer og ventende endringer er bevart.';
      }
    } finally {
      if (generation == _accountGeneration) {
        _cloudSyncing = false;
        notifyListeners();
      }
    }
  }

  // ── Trip sharing ─────────────────────────────────────────────
  /// Publishes a snapshot of [trip] under a shareable code and saves
  /// the code on the trip. Returns the code, or null when offline/
  /// signed out.
  Future<String?> shareTrip(Trip trip) async {
    if (localOnly) {
      lastError = 'Logg inn fra Mer for å dele med turkode.';
      notifyListeners();
      return null;
    }
    final code = await repo.publishTrip(trip);
    if (code != null) {
      trip.shareCode = code;
      await repo.saveTrip(trip);
      notifyListeners();
    }
    return code;
  }

  /// Stops sharing [trip] so its code no longer works. Returns a
  /// user-facing error message, or null on success.
  Future<String?> unshareTrip(Trip trip) async {
    final removed = await repo.unpublishTrip(trip);
    if (removed == null) {
      return 'Kunne ikke slutte å dele — sjekk at du er innlogget og på nett.';
    }
    if (!removed) return 'Bare den som delte turen kan slutte å dele den.';
    await repo.saveTrip(trip);
    notifyListeners();
    return null;
  }

  /// Fetches the trip published under [code] and imports it as a new
  /// local trip. The shared plan (route, dates, season, accommodation)
  /// is kept, while personal data is reset — each participant builds
  /// their own packing list, meal plan and recommendations from their
  /// own profile and settings. Returns the imported trip, or null on
  /// bad code/network failure.
  Future<Trip?> joinSharedTrip(String code) async {
    if (localOnly) {
      lastError = 'Logg inn fra Mer for å hente turkoder.';
      notifyListeners();
      return null;
    }
    final fetched = await repo.fetchSharedTrip(code);
    if (fetched == null) return null;
    // Fresh local id — the snapshot keeps the owner's trip id, which
    // would otherwise clobber our copy if we already had it.
    fetched.id = const Uuid().v4();
    fetched.name = fetched.name.isEmpty ? 'Delt tur' : fetched.name;
    // Reset owner-specific state — everyone makes their own lists.
    fetched.status = TripStatus.draft;
    fetched.participants = 1;
    fetched.packingList = [];
    fetched.mealPlan = null;
    fetched.recommendations = [];
    fetched.trackLog = [];
    fetched.review = null;
    fetched.alerts = [];
    fetched.avalancheWarnings = [];
    fetched.weather = {};
    trips.insert(0, fetched);
    currentTripId = fetched.id;
    await repo.saveTrip(fetched);
    notifyListeners();
    return fetched;
  }

  void selectTrip(String id) {
    currentTripId = id;
    notifyListeners();
  }

  Future<Trip> createTrip({String name = ''}) async {
    final trip = Trip(id: const Uuid().v4(), name: name);
    // The profile's preferred season becomes the trip's default —
    // packing lists then start with the right assumptions.
    if (profile.preferredSeason != null) {
      trip.season = profile.preferredSeason!;
    }
    trips.insert(0, trip);
    currentTripId = trip.id;
    await repo.saveTrip(trip);
    notifyListeners();
    return trip;
  }

  /// Deep-copies a trip (route, stages, packing, meals) into a new
  /// draft — handy for re-running a route another year. The track
  /// log, review and share timestamp are not copied.
  Future<Trip> duplicateTrip(Trip source) async {
    final j = source.toJson();
    j['id'] = const Uuid().v4();
    j['name'] = '${source.name.isEmpty ? 'Tur' : source.name} (kopi)';
    j['status'] = TripStatus.draft.name;
    j['trackLog'] = <dynamic>[];
    j['review'] = null;
    j['lastSharedAt'] = null;
    j['createdAt'] = DateTime.now().toIso8601String();
    j['updatedAt'] = DateTime.now().toIso8601String();
    final copy = Trip.fromJson(j);
    trips.insert(0, copy);
    currentTripId = copy.id;
    await repo.saveTrip(copy);
    notifyListeners();
    return copy;
  }

  Future<void> deleteTrip(String id) async {
    final deleted = trips.where((t) => t.id == id).firstOrNull;
    // A deleted trip should not stay readable via its share code.
    if (deleted?.shareCode != null && !localOnly) {
      unawaited(repo.unpublishTrip(deleted!));
    }
    trips.removeWhere((t) => t.id == id);
    if (currentTripId == id) {
      currentTripId = trips.isEmpty ? null : trips.first.id;
    }
    notifyListeners();
    try {
      await repo.deleteTrip(id);
    } catch (_) {
      lastError = 'Kunne ikke slette turen permanent — prøv igjen.';
      notifyListeners();
    }
  }

  /// Re-inserts a previously deleted trip (undo). The list updates
  /// immediately; persistence to Hive and Firestore happens behind
  /// the scenes so a slow or failed save can't leave undo looking
  /// dead.
  Future<void> restoreTrip(Trip trip, {int? index}) async {
    if (trips.any((t) => t.id == trip.id)) return;
    final i = (index ?? 0).clamp(0, trips.length);
    trips.insert(i, trip);
    currentTripId = trip.id;
    notifyListeners();
    try {
      await repo.saveTrip(trip);
    } catch (_) {
      lastError = 'Kunne ikke lagre den gjenopprettede turen — prøv igjen.';
      notifyListeners();
    }
  }

  // ── Tour calendar (norgeskompasset.no arrangements) ────────
  final eventsService = EventsService();
  List<CalendarEvent> events = const [];
  DateTime? eventsFetchedAt;
  bool eventsLoading = false;
  String? eventsError;

  /// Loads the calendar: cached copy first (instant, works offline),
  /// then the network unless the cache is fresh (< 1 h) and not forced.
  Future<void> loadEvents({bool force = false}) async {
    if (eventsLoading) return;
    if (events.isEmpty) {
      final cached = repo.cachedEvents();
      events = EventsService.parse(jsonEncode({'events': cached.events}));
      eventsFetchedAt = cached.fetchedAt;
    }
    final fresh =
        eventsFetchedAt != null &&
        DateTime.now().difference(eventsFetchedAt!) < const Duration(hours: 1);
    if (fresh && !force && events.isNotEmpty) {
      notifyListeners();
      return;
    }
    eventsLoading = true;
    eventsError = null;
    notifyListeners();
    try {
      final fetched = await eventsService.fetch(refresh: force);
      events = fetched;
      eventsFetchedAt = DateTime.now();
      await repo.cacheEvents([for (final e in fetched) e.toJson()]);
    } catch (_) {
      eventsError = events.isEmpty
          ? 'Kunne ikke hente turkalenderen. Sjekk nettet og prøv igjen.'
          : 'Viser sist hentede kalender – kunne ikke oppdatere nå.';
    } finally {
      eventsLoading = false;
      notifyListeners();
    }
  }

  /// Creates a draft trip from an arrangement: name, dates and meeting
  /// place are filled in; the route is drawn by the user afterwards.
  Future<Trip> startFromEvent(CalendarEvent e) async {
    final start = DateTime(e.start.year, e.start.month, e.start.day);
    final endSrc = e.end ?? e.start;
    final end = DateTime(endSrc.year, endSrc.month, endSrc.day);
    final trip = Trip(
      id: const Uuid().v4(),
      name: e.title,
      startDate: start,
      endDate: end.isBefore(start) ? start : end,
    );
    trip.season = TurrutebaseService.seasonForDate(start);
    trip.accommodation = e.multiDay
        ? AccommodationType.cabin
        : AccommodationType.dayHike;
    trip.notes = [
      'Fellestur fra NorgesKompasset-kalenderen.',
      if (e.place.isNotEmpty) 'Oppmøte: ${e.place}',
      if (e.formatted != null) 'Tid: ${e.formatted}',
      'Påmelding og detaljer: ${e.url}',
    ].join('\n');
    _recomputeStages(trip);
    trip.packingList = packingEngine.generate(trip, profile: profile);
    recommendationEngine.refresh(trip, profile: profile);
    await repo.saveTrip(trip);
    trips.insert(0, trip);
    currentTripId = trip.id;
    notifyListeners();
    return trip;
  }

  // ── Tour catalog ────────────────────────────────────────────
  /// Published tours readable by all signed-in users. Loaded lazily
  /// when the map's explore mode is opened.
  List<CatalogTrip> catalog = const [];
  bool catalogLoaded = false;

  /// True when the signed-in uid is listed in config/admins.
  bool isAdmin = false;

  Future<void> loadCatalog({bool force = false}) async {
    if (localOnly) {
      lastError = 'Logg inn fra Mer for å åpne turkatalogen.';
      notifyListeners();
      return;
    }
    // Re-check the admin list on every load/refresh so a uid added in
    // the console takes effect without restarting the app.
    final wasAdmin = isAdmin;
    isAdmin = await repo.fetchIsAdmin();
    if (catalogLoaded && !force) {
      if (wasAdmin != isAdmin) notifyListeners();
      return;
    }
    // Admins also see entries hidden by reports, so they can review them.
    catalog = await repo.fetchCatalog(includeHidden: isAdmin);
    catalogLoaded = true;
    notifyListeners();
  }

  /// Removes any shared tour — the Firestore rules only allow this for
  /// uids in config/admins.
  Future<bool> adminDeleteCatalogEntry(CatalogTrip entry) async {
    if (!isAdmin) return false;
    final ok = await repo.deleteCatalogEntry(entry.id);
    if (ok) {
      catalog = [
        for (final e in catalog)
          if (e.id != entry.id) e,
      ];
      notifyListeners();
    }
    return ok;
  }

  /// Reports a catalog entry as inappropriate or misleading.
  Future<bool> reportCatalogEntry(CatalogTrip entry) async {
    if (localOnly) return false;
    final ok = await repo.reportCatalogEntry(entry.id);
    final uid = _syncedUid;
    if (ok && uid != null && !entry.reportedBy.contains(uid)) {
      entry.reportedBy.add(uid);
      notifyListeners();
    }
    return ok;
  }

  /// Publishes [trip]'s route as a catalog entry. Returns null when
  /// the trip has no route or the write fails.
  Future<bool> publishTripToCatalog(
    Trip trip, {
    String description = '',
    String region = '',
  }) async {
    if (localOnly) {
      lastError = 'Logg inn fra Mer for å publisere turer.';
      notifyListeners();
      return false;
    }
    final route = trip.route;
    if (route == null || !route.hasRoute) return false;
    final hardest = trip.stages.fold<DifficultyLevel>(
      DifficultyLevel.easy,
      (acc, s) => (s.difficulty?.level.index ?? 0) > acc.index
          ? s.difficulty!.level
          : acc,
    );
    final entry = CatalogTrip(
      id: '',
      ownerUid: '',
      name: trip.name.isEmpty ? 'Tur uten navn' : trip.name,
      description: description,
      region: region,
      route: HikingRoute.decode(route.encode()),
      difficulty: hardest,
      seasons: [trip.season],
      minLevel: hardest.index >= DifficultyLevel.challenging.index
          ? TourLevel.intermediate
          : TourLevel.novice,
      accommodation: trip.accommodation,
      activity: trip.activity,
      durationDays: trip.hikingDays.clamp(1, 14).toInt(),
    );
    final id = await repo.publishToCatalog(entry);
    if (id == null) return false;
    catalogLoaded = false; // refetch so the new entry shows up
    return true;
  }

  /// Creates a fresh local trip from a catalog entry — the route is
  /// deep-copied so the user's trip stays independent of the shared
  /// snapshot.
  Future<Trip> startFromCatalog(
    CatalogTrip c, {
    DateTime? startDate,
    int? days,
    TripActivity? activity,
    TripSeason? season,
    AccommodationType? accommodation,
    CarryMode? carry,
    int participants = 1,
  }) async {
    if (participants < 1 || participants > 20) {
      throw ArgumentError.value(participants, 'participants');
    }
    final date = startDate == null
        ? null
        : DateTime.utc(startDate.year, startDate.month, startDate.day);
    final daysClamped = (days ?? c.durationDays).clamp(1, 14).toInt();
    final trip = Trip(
      id: const Uuid().v4(),
      name: c.name,
      startDate: date,
      endDate: date?.add(Duration(days: daysClamped - 1)),
      season: season ?? c.seasons.firstOrNull ?? TripSeason.summer,
      activity: activity ?? c.activity,
      accommodation: accommodation ?? c.accommodation,
      carry:
          carry ??
          ((activity ?? c.activity) == TripActivity.paddle
              ? CarryMode.canoe
              : CarryMode.backpack),
      participants: participants,
      route: HikingRoute.decode(c.route.encode()),
      notes:
          '${c.description}\nBrukerpublisert tur, ikke kontrollert av NorgesKompasset.',
    );
    _recomputeStages(trip);
    trip.packingList = packingEngine.generate(trip, profile: profile);
    final cond = packingEngine.conditionsFor(trip, profile);
    final estimate = estimateDailyKcal(
      trip,
      bodyKg: profile.weightKg > 0 ? profile.weightKg : 75,
      minTempC: cond.minTemp,
    );
    trip.mealPlan = MealPlanner.generate(
      trip,
      profile: profile,
      targetKcalPerDay: estimate.kcalPerDay,
    );
    _syncFoodToPacking(trip);
    recommendationEngine.refresh(trip, profile: profile);
    await repo.saveTrip(trip);
    trips.insert(0, trip);
    currentTripId = trip.id;
    notifyListeners();
    return trip;
  }

  /// Creates a trip directly from a Kartverket trail — one tap gives
  /// the user a committed route, then elevation, forecast, packing
  /// list and meal plan are generated in sequence. The trail is
  /// registered data, so the source is [RouteSource.trail]; activity
  /// and season follow the trail type and calendar.
  Future<Trip> startFromTrail(TrailRoute t) async {
    final trip = Trip(
      id: const Uuid().v4(),
      name: t.name.isEmpty ? t.typeLabel : t.name,
      activity: switch (t.type) {
        TrailType.ski => TripActivity.ski,
        TrailType.bike => TripActivity.bike,
        _ => TripActivity.foot,
      },
      season: t.type == TrailType.ski
          ? TripSeason.winter
          : TurrutebaseService.seasonForDate(DateTime.now()),
      accommodation: AccommodationType.tent,
      route: HikingRoute(
        points: [for (final p in t.points) RoutePoint(p.lat, p.lon)],
        waypoints: [
          Waypoint(
            id: '${t.id}-a',
            name: 'Start (A)',
            lat: t.points.first.lat,
            lon: t.points.first.lon,
            type: WaypointType.start,
          ),
          Waypoint(
            id: '${t.id}-b',
            name: 'Mål (B)',
            lat: t.points.last.lat,
            lon: t.points.last.lon,
            type: WaypointType.end,
          ),
        ],
        source: RouteSource.trail,
        distanceMeters: t.distanceMeters,
      ),
      notes:
          'Rute hentet fra Kartverkets turrutebase — registrert '
          '${t.typeLabel.toLowerCase()}${t.maintainer.isEmpty ? '' : ' (${t.maintainer})'}. '
          'Kartdata, ikke bekreftet fremkommelighet i terrenget.',
    );
    trips.insert(0, trip);
    currentTripId = trip.id;
    await _commitRoute(trip);
    notifyListeners();
    // Background chain: heights → forecast → packing → meals. Each
    // step handles its own errors and reports via busy/lastError.
    unawaited(
      fetchElevation(trip)
          .then((_) => fetchWeather(trip))
          .then((_) => generatePackingList(trip))
          .then((_) => generateMealPlan(trip))
          .catchError((_) {}),
    );
    return trip;
  }

  // ── Onboarding ────────────────────────────────────────────
  /// First-run intro cards — shown once, persisted in settings.
  bool get onboardingSeen => repo.onboardingSeen;

  Future<void> markOnboardingSeen() async {
    await repo.saveOnboardingSeen();
    notifyListeners();
  }

  // ── Theme ─────────────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await repo.saveThemeModePref(mode.name);
    notifyListeners();
  }

  void _loadThemeMode() {
    _themeMode = switch (repo.themeModePref) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  // ── Profile ────────────────────────────────────────────────

  Future<void> updateProfile(UserProfile p) async {
    profile = p;
    await repo.saveProfile(p);
    // Re-assess the active trip against the updated level.
    final trip = currentTrip;
    if (trip != null) {
      try {
        recommendationEngine.refresh(trip, profile: profile);
        await repo.saveTrip(trip);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveTrip(Trip trip) async {
    // A draft becomes 'planned' once it has both a route and dates.
    if (trip.status == TripStatus.draft &&
        trip.route?.hasRoute == true &&
        trip.startDate != null) {
      trip.status = TripStatus.planned;
    }
    trip.updatedAt = DateTime.now();
    await repo.saveTrip(trip);
    notifyListeners();
  }

  Future<void> _run(String label, Future<void> Function() work) async {
    busy = true;
    busyLabel = label;
    lastError = null;
    notifyListeners();
    try {
      await work();
    } on ServiceException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = 'Noe gikk galt: $e';
    } finally {
      busy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  // ── Route ──────────────────────────────────────────────────

  /// Sets a trip's route from anchor points. Tries trail routing first;
  /// falls back to a straight-line estimated route.
  Future<void> buildRoute(
    Trip trip,
    List<LatLng> anchors, {
    required List<Waypoint> waypoints,
  }) async {
    await _run('Beregner rute…', () async {
      List<RoutePoint> points;
      RouteSource source;
      List<({int start, int end})> straightRanges = const [];
      // Legs the user marked as straight never reach the router.
      final straightLegs = <int>{
        for (var i = 1; i < waypoints.length && i < anchors.length; i++)
          if (waypoints[i].straightLeg) i,
      };
      try {
        // Each activity gets its own BRouter profile — hiking trails,
        // ways carrying nordic pistes, cycleways or waterways. Legs
        // outside mapped terrain degrade to honest straight lines.
        final result = await routingService.routeAlongTrails(
          anchors,
          straightLegs: straightLegs,
          profile: switch (trip.activity) {
            TripActivity.ski => RoutingService.profileSki,
            TripActivity.bike => RoutingService.profileBike,
            TripActivity.paddle => RoutingService.profilePaddle,
            _ => RoutingService.profileHiking,
          },
        );
        points = result.points;
        straightRanges = result.straightRanges;
        source = result.routedLegs == result.totalLegs
            ? RouteSource.trail
            : result.routedLegs > 0
            ? RouteSource.mixed
            : RouteSource.estimated;
        if (result.routedLegs < result.totalLegs && result.routedLegs > 0) {
          lastError =
              '${result.totalLegs - result.routedLegs} av ${result.totalLegs} strekninger kunne ikke ruttes langs sti – de vises som rette linjer.';
        } else if (result.routedLegs == 0) {
          lastError = 'Fant ingen stirute – viser estimert luftlinje i stedet.';
        }
      } on ServiceException catch (e) {
        points = routingService.straightLine(anchors);
        source = RouteSource.estimated;
        lastError = '${e.message} Viser estimert rute (luftlinje).';
      }
      final distance = routeDistanceMeters(points);
      // «Tur-retur» is a property of the trip, not of one calculation
      // — keep it when the route is regenerated.
      final keepOutAndBack = trip.route?.outAndBack == true;
      trip.route = HikingRoute(
        points: points,
        waypoints: waypoints,
        source: source,
        distanceMeters: distance,
        straightRanges: straightRanges,
      );
      if (keepOutAndBack) trip.route!.makeOutAndBack();
      await _commitRoute(trip);
    });
  }

  /// Shared tail when a trip gets a new route: cached weather is
  /// stale for the new geometry, stages are rebuilt right away (the
  /// time estimate is distance-based and needs no elevation), and
  /// the trip is persisted.
  Future<void> _commitRoute(Trip trip) async {
    trip.weather = {};
    trip.alerts = [];
    trip.avalancheWarnings = [];
    trip.avalancheTerrain = null;
    _recomputeStages(trip);
    await _refreshPlan(trip, generateMissing: true);
  }

  /// Rebuilds generated advice from current route/setup while keeping
  /// personal packing overrides and manually edited/menu meals intact.
  Future<void> _refreshPlan(Trip trip, {bool generateMissing = false}) async {
    if (generateMissing || trip.packingList.isNotEmpty) {
      final past = trips
          .where((t) => t.id != trip.id && t.review != null)
          .toList();
      trip.packingList = packingEngine.generate(
        trip,
        pastTrips: past,
        profile: profile,
      );
    }
    final previous = trip.mealPlan;
    if (previous != null || generateMissing) {
      if (previous == null ||
          previous.meals.every(
            (meal) => !meal.userEdited && meal.sourceMenuId == null,
          )) {
        final cond = packingEngine.conditionsFor(trip, profile);
        final bodyKg = profile.weightKg > 0 ? profile.weightKg : 75.0;
        final estimate = estimateDailyKcal(
          trip,
          bodyKg: bodyKg,
          minTempC: cond.minTemp,
        );
        final rebuilt = MealPlanner.generate(
          trip,
          profile: profile,
          targetKcalPerDay: estimate.kcalPerDay,
        );
        if (previous != null) {
          rebuilt.checkedShoppingItems.addAll(
            previous.checkedShoppingItems.intersection(
              rebuilt.shoppingList.toSet(),
            ),
          );
        }
        trip.mealPlan = rebuilt;
      } else {
        previous.days = trip.hikingDays;
        previous.people = trip.participants;
      }
      _syncFoodToPacking(trip);
    }
    try {
      recommendationEngine.refresh(trip, profile: profile);
    } catch (_) {
      // A recommendation failure must not block a saved route or list.
    }
    await repo.saveTrip(trip);
    notifyListeners();
  }

  Future<void> clearRoute(Trip trip) async {
    trip.route = null;
    trip.stages = [];
    trip.weather = {};
    trip.alerts = [];
    trip.avalancheWarnings = [];
    trip.avalancheTerrain = null;
    await _refreshPlan(trip);
  }

  /// Imports a parsed GPX document as the trip's route.
  /// Marked [RouteSource.manual] — an imported track is real data but
  /// has not been verified against current trail conditions.
  Future<void> importRoute(
    Trip trip,
    List<RoutePoint> points,
    List<Waypoint> gpxWaypoints,
  ) async {
    await _run('Importerer rute…', () async {
      final waypoints = <Waypoint>[
        Waypoint(
          id: '${trip.id}-a',
          name: gpxWaypoints.isNotEmpty ? gpxWaypoints.first.name : 'Start (A)',
          lat: points.first.lat,
          lon: points.first.lon,
          type: WaypointType.start,
        ),
        for (final w in gpxWaypoints.skip(1)) w,
        Waypoint(
          id: '${trip.id}-b',
          name: 'Mål (B)',
          lat: points.last.lat,
          lon: points.last.lon,
          type: WaypointType.end,
        ),
      ];
      trip.route = HikingRoute(
        points: points,
        waypoints: waypoints,
        source: RouteSource.manual,
        distanceMeters: routeDistanceMeters(points),
      );
      await _commitRoute(trip);
    });
  }

  /// Fetches elevation for route points, recomputes stats. Re-runs
  /// stage analysis afterwards so everything stays consistent.
  static const elevationBusyLabel = 'Henter høydedata…';

  Future<void> fetchElevation(Trip trip) async {
    final route = trip.route;
    if (route == null || !route.hasRoute) return;
    await _run(elevationBusyLabel, () async {
      try {
        await elevationService.fetchElevations(route.points);
        final stats = elevationStats(route.points);
        route.totalAscent = stats.ascent;
        route.totalDescent = stats.descent;
        route.highestPoint = stats.highest;
      } finally {
        // Even when the fetch fails, keep stages in sync with the
        // current route — the summary must never end up saved with
        // a route but no stages.
        _recomputeStages(trip);
        await repo.saveTrip(trip);
      }
    });
  }

  /// Toggles «tur-retur»: the way back mirrors the way out, so every
  /// derived number (distance, time, ascent, stages, packing) covers
  /// the whole trip. Weather is per stage midpoint and is refetched.
  Future<void> setOutAndBack(Trip trip, bool on) async {
    final route = trip.route;
    if (route == null || !route.hasRoute || route.outAndBack == on) return;
    if (on) {
      route.makeOutAndBack();
    } else {
      route.makeOneWay();
    }
    trip.weather = {};
    _recomputeStages(trip);
    await _refreshPlan(trip);
  }

  /// Recomputes stage splits, stats, dates and difficulty for the trip.
  void _recomputeStages(Trip trip) => StageBuilder.recompute(trip);

  /// Rebuilds stages and regenerates dependent data.
  Future<void> reanalyze(Trip trip, {bool datesChanged = false}) async {
    if (datesChanged) {
      trip.weather = {};
      trip.alerts = [];
      trip.avalancheWarnings = [];
    }
    _recomputeStages(trip);
    await _refreshPlan(trip);
  }

  // ── Weather ────────────────────────────────────────────────

  /// Fetches a forecast for the representative point of each stage
  /// (stage midpoint with stage elevation for altitude correction).
  Future<void> fetchWeather(Trip trip) async {
    if (trip.stages.isEmpty && trip.route?.hasRoute != true) return;
    await _run('Henter værprognose…', () async {
      final basisBefore = PackingChange.basisOf(
        packingEngine.conditionsFor(trip, profile),
      );
      final listBefore = [...trip.packingList];
      final targets = <({String key, double lat, double lon, double? ele})>[];
      if (trip.stages.isNotEmpty) {
        for (final s in trip.stages) {
          if (s.points.isEmpty) continue;
          final eles = s.points
              .map((p) => p.elevation)
              .whereType<double>()
              .toList();
          final meanEle = eles.isEmpty
              ? null
              : eles.reduce((a, b) => a + b) / eles.length;
          // Sample start, midpoint and end of the stage so the forecast
          // reflects variation along the stage — not just one point.
          final reps = <({String suffix, RoutePoint p})>[
            (suffix: 'a', p: s.points.first),
            (suffix: 'b', p: s.points[s.points.length ~/ 2]),
            (suffix: 'c', p: s.points.last),
          ];
          var idx = 0;
          RoutePoint? last;
          for (final r in reps) {
            // Skip points closer than ~500 m to the previous sample —
            // the same forecast would apply anyway.
            if (last != null && metersBetween(last.latLng, r.p.latLng) < 500) {
              continue;
            }
            targets.add((
              key: '${s.id}-$idx',
              lat: r.p.lat,
              lon: r.p.lon,
              ele: meanEle,
            ));
            last = r.p;
            idx++;
          }
        }
      } else {
        final route = trip.route!;
        final mid = route.points[route.points.length ~/ 2];
        targets.add((key: 'route', lat: mid.lat, lon: mid.lon, ele: null));
      }
      // Fetch in small parallel batches — sequential fetches made a
      // 9-point multi-day forecast take ~10× longer than needed.
      const batchSize = 4;
      for (var i = 0; i < targets.length; i += batchSize) {
        final snaps = await Future.wait(
          targets
              .skip(i)
              .take(batchSize)
              .map(
                (t) => weatherService.fetchForecast(
                  t.lat,
                  t.lon,
                  elevation: t.ele,
                ),
              ),
        );
        for (var j = 0; j < snaps.length; j++) {
          trip.weather[targets[i + j].key] = snaps[j];
        }
      }
      // Official warnings along the route — sampled at stage midpoints,
      // deduplicated by alert id. A failed alerts call must not break
      // the weather fetch.
      try {
        final seen = <String>{};
        final alerts = <MetAlert>[];
        final alertTargets = <LatLng>[
          if (trip.stages.isNotEmpty)
            for (final s in trip.stages)
              if (s.points.isNotEmpty)
                s.points[s.points.length ~/ 2].latLng
              else if (trip.route?.hasRoute == true)
                trip.route!.points[trip.route!.points.length ~/ 2].latLng,
        ];
        final results = await Future.wait(
          alertTargets.map(
            (ll) => weatherService.fetchAlerts(ll.latitude, ll.longitude),
          ),
        );
        for (final list in results) {
          for (final a in list) {
            if (seen.add('${a.id}|${a.event}')) alerts.add(a);
          }
        }
        trip.alerts = alerts;
      } catch (_) {
        trip.alerts = trip.alerts; // keep previously fetched alerts
      }
      // Avalanche warnings (Varsom/NVE) for the same sampled points
      // and the trip's date window. Outside the warning season or
      // beyond the few-day forecast horizon this simply returns empty.
      try {
        final from = trip.startDate ?? DateTime.now();
        final to = trip.endDate ?? from.add(const Duration(days: 2));
        final avTargets = <LatLng>[
          if (trip.stages.isNotEmpty)
            for (final s in trip.stages)
              if (s.points.isNotEmpty)
                s.points[s.points.length ~/ 2].latLng
              else if (trip.route?.hasRoute == true)
                trip.route!.points[trip.route!.points.length ~/ 2].latLng,
        ];
        final avResults = await Future.wait(
          avTargets.map(
            (ll) => varsomService.fetchWarnings(
              ll.latitude,
              ll.longitude,
              from,
              to,
            ),
          ),
        );
        final seen = <String>{};
        trip.avalancheWarnings = [
          for (final list in avResults)
            for (final w in list)
              if (seen.add(w.regId)) w,
        ];
      } catch (_) {
        // Varsom failure must not break weather fetch — keep old data.
      }
      // The packing rules read the forecast (min temp, rain, wind,
      // freezing nights) — regenerate so the list reflects it.
      await _refreshPlan(trip);
      if (listBefore.isNotEmpty) {
        final change = PackingChange.diff(
          before: basisBefore,
          after: PackingChange.basisOf(
            packingEngine.conditionsFor(trip, profile),
          ),
          oldList: listBefore,
          newList: trip.packingList,
        );
        if (change.isEmpty) {
          packingChanges.remove(trip.id);
        } else {
          packingChanges[trip.id] = change;
        }
      }
      recommendationEngine.refresh(trip, profile: profile);
      await repo.saveTrip(trip);
    });
  }

  // ── Offline map ──────────────────────────────────────────

  /// Estimated number of tiles needed to cover this trip's route.
  /// Memoized per route geometry — the tile scan runs on every rebuild
  /// otherwise (home card + safety card both call it).
  final _tilesNeededCache =
      <
        String,
        ({HikingRoute route, List<RoutePoint> points, List<String> urls})
      >{};
  final _coverageCache =
      <String, ({List<String> urls, int revision, int cached})>{};

  List<String> _offlineUrls(Trip trip) {
    final route = trip.route;
    if (route == null || !route.hasRoute) return const [];
    final cached = _tilesNeededCache[trip.id];
    if (cached != null &&
        identical(cached.route, route) &&
        identical(cached.points, route.points)) {
      return cached.urls;
    }
    final urls = List<String>.unmodifiable(
      TileCache.urlsCovering(route.latLngs),
    );
    _tilesNeededCache[trip.id] = (
      route: route,
      points: route.points,
      urls: urls,
    );
    return urls;
  }

  int mapTilesNeeded(Trip trip) => _offlineUrls(trip).length;

  /// Empties the persistent map-tile cache.
  Future<void> clearMapCache() async {
    await TileCache.clear();
    _tilesNeededCache.clear();
    notifyListeners();
  }

  int get mapTilesCached => TileCache.count;

  ({int cached, int total}) offlineCoverage(Trip trip) {
    final urls = _offlineUrls(trip);
    var cached = _coverageCache[trip.id];
    if (cached == null ||
        !identical(cached.urls, urls) ||
        cached.revision != TileCache.revision) {
      cached = (
        urls: urls,
        revision: TileCache.revision,
        cached: urls.where(TileCache.isCached).length,
      );
      _coverageCache[trip.id] = cached;
    }
    return (cached: cached.cached, total: urls.length);
  }

  /// Progress of an in-flight tile download (done/total), null when idle.
  /// Kept out of [busy] so the app stays usable while tiles download
  /// in the background.
  int? tilesDone;
  int? tilesTotal;
  bool _cancelTiles = false;

  /// Pre-downloads map tiles covering the whole route so the map
  /// works offline along it. Skips tiles already in the cache.
  Future<void> downloadMapTiles(Trip trip) async {
    final pts = trip.route?.latLngs ?? [];
    if (pts.isEmpty) {
      lastError = 'Turen har ingen rute ennå – beregn ruten først.';
      notifyListeners();
      return;
    }
    if (tilesTotal != null && tilesDone != tilesTotal) return;
    final urls = TileCache.urlsCovering(pts);
    _cancelTiles = false;
    tilesDone = 0;
    tilesTotal = urls.length;
    lastError = null;
    notifyListeners();
    try {
      await TileCache.prefetch(
        urls,
        isCancelled: () => _cancelTiles,
        onProgress: (done, total) {
          // Throttle rebuilds — one notification per ~10 tiles keeps
          // the UI live without repainting the whole app per tile.
          final prev = tilesDone;
          tilesDone = done;
          if (done - (prev ?? 0) >= 10 || done == total) {
            notifyListeners();
          }
        },
      );
      if (!_cancelTiles) {
        final coverage = offlineCoverage(trip);
        lastError = coverage.cached == coverage.total && coverage.total > 0
            ? 'Kartutsnittet er lagret på de valgte zoomnivåene. Test i flymodus før turen.'
            : 'Bare ${coverage.cached}/${coverage.total} kartfliser er lagret. Prøv igjen på nett.';
      }
    } finally {
      tilesDone = null;
      tilesTotal = null;
      notifyListeners();
    }
  }

  void cancelMapDownload() => _cancelTiles = true;

  // ── Track recording ───────────────────────────────────────

  /// Appends a GPS position to the trip's track log. Persists every
  /// 10th point to avoid a write on every GPS tick — a full save also
  /// happens via [saveTrackNow] (e.g. when tracking stops). Listeners
  /// are notified every 5th point, not per tick — a GPS fix every ~5 m
  /// would otherwise rebuild every mounted screen far too often.
  Future<void> recordTrackPoint(Trip trip, TrackPoint p) async {
    final log = [...trip.trackLog, p];
    trip.trackLog = log;
    if (log.length % 10 == 0) {
      await _persistTrack(trip);
    }
    if (log.length % 5 == 0) {
      trackRevision.value++;
    }
  }

  Future<void> saveTrackNow(Trip trip) async {
    await _persistTrack(trip, forceSync: true);
    notifyListeners();
  }

  /// Upper bound on stored track points — a Firestore document caps at
  /// ~1 MB, and a week-long high-frequency log would otherwise grow
  /// without limit. Simplification keeps the shape within a few
  /// meters while shrinking storage dramatically.
  static const int _trackPointCap = 3000;

  /// How often track saves are pushed to the cloud. Local Hive saves
  /// stay at every 10th point; the network push is throttled so a long
  /// hike doesn't mean hundreds of Firestore writes.
  static const _trackSyncInterval = Duration(minutes: 2);
  DateTime? _lastTrackSync;

  Future<void> _persistTrack(Trip trip, {bool forceSync = false}) async {
    // Only simplify when the log actually exceeds the cap — running
    // Douglas-Peucker over the whole log on every persist is wasted
    // work for the common case (shorter hikes stay under the cap).
    if (trip.trackLog.length > _trackPointCap) {
      var tolerance = 5.0; // meters
      var log = simplifyPolyline(
        trip.trackLog,
        tolerance,
        (p) => LatLng(p.lat, p.lon),
      );
      while (log.length > _trackPointCap && tolerance < 80) {
        tolerance *= 2;
        log = simplifyPolyline(
          trip.trackLog,
          tolerance,
          (p) => LatLng(p.lat, p.lon),
        );
      }
      trip.trackLog = log;
    }
    final now = DateTime.now();
    final due =
        forceSync ||
        _lastTrackSync == null ||
        now.difference(_lastTrackSync!) >= _trackSyncInterval;
    if (due) _lastTrackSync = now;
    await repo.saveTrip(trip, syncCloud: due);
  }

  /// Applies a participant-count change to everything sized per
  /// person: the meal plan's people count (all meal quantities are
  /// per-person, so totals rescale immediately) and the packing list.
  Future<void> updateParticipants(Trip trip) async {
    trip.mealPlan?.people = trip.participants;
    await updateTripSetup(trip);
  }

  /// Rebuilds trip-setup-dependent data after the user changes
  /// accommodation, season or carry mode. The packing list is
  /// regenerated (packed state and user weights are preserved by the
  /// engine) so changed assumptions take effect immediately.
  Future<void> updateTripSetup(Trip trip) async {
    _recomputeStages(trip);
    await _refreshPlan(trip);
  }

  // ── Packing ────────────────────────────────────────────────

  /// Applies a packing preset: sets activity, carry mode, accommodation
  /// and season on the trip, then regenerates the list. The rule matrix
  /// still decides every item — presets only pick the parameters.
  Future<void> applyPackingPreset(Trip trip, PackingPreset preset) async {
    preset.apply(trip);
    _recomputeStages(trip);
    await generatePackingList(trip);
  }

  Future<void> generatePackingList(Trip trip) async {
    // Earlier trips feed the learning: their reviews mark items as
    // unnecessary/missing on this new list.
    final past = trips
        .where((t) => t.id != trip.id && t.review != null)
        .toList();
    trip.packingList = packingEngine.generate(
      trip,
      pastTrips: past,
      profile: profile,
    );
    _syncFoodToPacking(trip);
    recommendationEngine.refresh(trip, profile: profile);
    await repo.saveTrip(trip);
    notifyListeners();
  }

  Future<void> updatePackingItem(Trip trip, PackingItem item) async {
    await repo.saveTrip(trip);
    notifyListeners();
  }

  Future<void> applyTemplate(Trip trip, List<PackingItem> items) async {
    final merged = <PackingItem>[...trip.packingList];
    for (final t in items) {
      if (!merged.any((i) => i.name.toLowerCase() == t.name.toLowerCase())) {
        final copy = t.copy()
          ..packed = false
          ..userAdded = true;
        merged.add(copy);
      }
    }
    trip.packingList = merged;
    await repo.saveTrip(trip);
    notifyListeners();
  }

  // ── Meals ──────────────────────────────────────────────────

  Future<void> applyFoodMenu(Trip trip, FoodMenu menu, {int? day}) async {
    trip.mealPlan = MealPlanner.applyMenu(
      trip,
      menu,
      day: day,
      profile: profile,
    );
    await updateMealPlan(trip);
  }

  Future<void> generateMealPlan(Trip trip) async {
    // Route-aware target: distance, ascent, pack weight and the
    // coldest forecast temperature feed the portion scaling.
    final cond = packingEngine.conditionsFor(trip, profile);
    final bodyKg = profile.weightKg > 0 ? profile.weightKg : 75.0;
    final est = estimateDailyKcal(trip, bodyKg: bodyKg, minTempC: cond.minTemp);
    trip.mealPlan = MealPlanner.generate(
      trip,
      profile: profile,
      targetKcalPerDay: est.kcalPerDay,
    );
    // Food weight flows into the packing list as consumable items.
    _syncFoodToPacking(trip);
    await repo.saveTrip(trip);
    notifyListeners();
  }

  /// Persists edits to the existing meal plan without regenerating it.
  Future<void> updateMealPlan(Trip trip) async {
    _syncFoodToPacking(trip);
    await repo.saveTrip(trip);
    notifyListeners();
  }

  void _syncFoodToPacking(Trip trip) {
    final plan = trip.mealPlan;
    if (plan == null) return;
    final existingFood = _takeGeneratedMealItem(
      trip,
      id: 'food-total',
      category: PackingCategory.food,
      namePrefix: 'Mat for ',
    );
    if (plan.totalFoodWeightGrams > 0 &&
        !trip.deletedGearIds.contains('food-total')) {
      trip.packingList.add(
        _mergeGeneratedMealItem(
          PackingItem(
            id: 'food-total',
            name:
                'Mat for ${fmtCount(plan.days, 'dag', 'dager')} (${fmtCount(plan.meals.length, 'måltid', 'måltider')})',
            category: PackingCategory.food,
            quantity: 1,
            unitWeightGrams: plan.totalFoodWeightGrams,
            priority: PackingPriority.required,
            reason: 'Generert fra måltidsplanen',
          ),
          existingFood,
        ),
      );
    }
    final existingWater = _takeGeneratedMealItem(
      trip,
      id: 'water-total',
      category: PackingCategory.water,
      namePrefix: 'Vann (',
    );
    if (plan.totalWaterWeightGrams > 0 &&
        !trip.deletedGearIds.contains('water-total')) {
      trip.packingList.add(
        _mergeGeneratedMealItem(
          PackingItem(
            id: 'water-total',
            name:
                'Vann (${plan.waterLitersPerPersonDay.toStringAsFixed(1)} l/person/dag)',
            category: PackingCategory.water,
            quantity: 1,
            unitWeightGrams: plan.totalWaterWeightGrams,
            priority: PackingPriority.recommended,
            reason: 'Estimat – juster etter vanntilgang langs ruten',
          ),
          existingWater,
        ),
      );
    }
  }

  /// Removes only the generated meal totals. Other generated consumables
  /// (for example dog food from the gear catalog) must stay in place.
  PackingItem? _takeGeneratedMealItem(
    Trip trip, {
    required String id,
    required PackingCategory category,
    required String namePrefix,
  }) {
    bool matches(PackingItem item) =>
        !item.userAdded &&
        (item.id == id ||
            (item.category == category && item.name.startsWith(namePrefix)));
    final existing = trip.packingList.where(matches).firstOrNull;
    trip.packingList.removeWhere(matches);
    return existing;
  }

  PackingItem _mergeGeneratedMealItem(
    PackingItem generated,
    PackingItem? existing,
  ) {
    if (existing == null) return generated;
    generated.packed = existing.packed;
    generated.worn = existing.worn;
    generated.consumable = existing.consumable;
    generated.needsAcquisition = existing.needsAcquisition;
    generated.nameEdited = existing.nameEdited;
    generated.quantityEdited = existing.quantityEdited;
    generated.priorityEdited = existing.priorityEdited;
    generated.weightEdited = existing.weightEdited;
    if (generated.nameEdited) generated.name = existing.name;
    if (generated.quantityEdited) generated.quantity = existing.quantity;
    if (generated.priorityEdited) generated.priority = existing.priority;
    if (generated.weightEdited) {
      generated.unitWeightGrams = existing.unitWeightGrams;
    }
    return generated;
  }

  // ── Status transitions ─────────────────────────────────────

  Future<void> setStatus(Trip trip, TripStatus status) async {
    trip.status = status;
    await repo.saveTrip(trip);
    notifyListeners();
  }

  Future<void> saveReview(Trip trip, TripReview review) async {
    trip.review = review;
    trip.status = TripStatus.completed;
    await repo.saveTrip(trip);
    notifyListeners();
  }
}
