import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';
import '../services/geocoding_service.dart';
import '../services/gpx_service.dart';
import '../services/map_display_settings.dart';
import '../services/turrutebase_service.dart';
import '../services/weather_service.dart' show ServiceException;
import '../services/tile_cache.dart';
import '../services/weather_service.dart';
import '../state/app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'elevation_screen.dart';

/// Kartverket topo tiles (free) with OSM fallback.
const _kartverketTopo =
    'https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png';
const _openTopoMap = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
const _osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
// OpenSnowMap pistes (OSM data) — transparent overlay of nordic
// and downhill ski trails drawn on top of the base map.
const _openSnowMap = 'https://tiles.opensnowmap.org/pistes/{z}/{x}/{y}.png';

enum _TapMode { auto, start, end, waypoint, direct }

class MapPlannerScreen extends StatefulWidget {
  /// Optional point to highlight — used when a position is pushed
  /// from e.g. the elevation profile. The map centers on it and shows
  /// a distinct marker.
  final LatLng? highlight;
  const MapPlannerScreen({super.key, this.highlight});

  @override
  State<MapPlannerScreen> createState() => _MapPlannerScreenState();
}

class _MapPlannerScreenState extends State<MapPlannerScreen> {
  final _mapCtrl = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<PlaceResult> _results = [];
  bool _searching = false;
  String? _searchError;
  int _searchGeneration = 0;
  _TapMode _tapMode = _TapMode.auto;
  final _mapSettings = MapDisplaySettings();
  double? _mapZoom;
  bool _showConfig = false;
  bool _showAdvanced = false;
  bool _locating = false;

  /// Last accepted user fix — drawn as a position dot on the map.
  LatLng? _userLatLng;

  // Loop generator state — seed rotates the candidate bearings so
  // "Ny variant" produces a different loop each time.
  double _loopKm = 15;
  int _loopSeed = 0;
  bool _loopGenerated = false;

  // OpenSnowMap ski-trail overlay (toggled from the map).
  bool get _skiOverlay => _mapSettings.skiFor(_trip?.activity);

  // Turrutebase layer — official Kartverket trails fetched per
  // viewport (WFS/GML). All types are fetched; the season decides
  // which are emphasized (ski tracks Nov–Apr / on winter trips,
  // foot/bike otherwise) — coverage is too patchy to hide the rest.
  bool _trailLayer = false;
  List<TrailRoute> _trails = [];
  LatLngBounds? _trailFetchedBounds;
  Timer? _trailDebounce;
  int _trailGeneration = 0;
  bool _trailLoading = false;
  String? _trailError;
  Set<TrailType> _seasonalTypes = {};

  // Working waypoint anchors for the trip being edited.
  final List<Waypoint> _anchors = [];

  Trip? get _trip => context.read<AppState>().currentTrip;
  String? _anchorsFromTripId;
  bool _directHintShown = false;
  // True when anchors were edited after the last route calculation —
  // the drawn route then no longer matches the waypoint list.
  bool _routeDirty = false;

  /// Extra room for the search bar (top), map buttons (right) and tap
  /// mode chips (bottom) so start and goal markers are never hidden.
  static const _routeFitPadding = EdgeInsets.fromLTRB(56, 96, 88, 88);
  final _nameLookups = <Future<void>>{};

  /// Waypoint id being repositioned — the next map tap moves it.
  String? _moveId;

  bool get _isTouchPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _centerOnUser();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs whenever the watched AppState notifies; _loadFromTrip only
    // resets when the trip id actually changed.
    _loadFromTrip();
  }

  /// Centers the map on the user's position at startup — only when
  /// there is no route/anchor to show instead. Last-known fix first
  /// (instant); when it is missing or unusable we try one fresh fix.
  /// Fails silently to the default mountain-area view when permission
  /// or GPS is unavailable.
  Future<void> _centerOnUser() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      // A cached fix that fails the sanity checks must not decide the
      // map view — Windows can report a stale network-based position.
      if (pos == null || !_usablePosition(pos)) {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      }
      if (!mounted || !_usablePosition(pos)) return;
      // Don't steal the view if the trip already has content.
      if (widget.highlight != null ||
          _anchors.isNotEmpty ||
          _trip?.route?.hasRoute == true) {
        return;
      }
      _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 11);
    } catch (_) {
      // No position available — keep the default overview.
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _trailDebounce?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  /// Fetches registered Turrutebase trails for the visible area when
  /// the trail layer is on. Debounced and skipped while the camera
  /// still shows an area already covered.
  void _onCameraMoved(MapCamera cam, bool hasGesture) {
    final previousZoom = _mapZoom;
    _mapZoom = cam.zoom;
    if (previousZoom == null || (previousZoom < 6) != (cam.zoom < 6)) {
      if (mounted) setState(() {});
    }
    final bounds = cam.visibleBounds;
    if (_trailLayer && cam.zoom >= 8) {
      final f = _trailFetchedBounds;
      if (f == null ||
          bounds.south < f.south ||
          bounds.north > f.north ||
          bounds.west < f.west ||
          bounds.east > f.east) {
        _trailDebounce?.cancel();
        _trailDebounce = Timer(
          const Duration(milliseconds: 700),
          () => _fetchTrails(bounds),
        );
      }
    }
  }

  /// Fetches Turrutebase trails for the visible area. Feature types
  /// follow the season (ski tracks on winter trips/Nov–Apr, foot and
  /// bike routes otherwise). Debounced per bounds like the POI layer.
  Future<void> _fetchTrails(LatLngBounds bounds) async {
    if (!_trailLayer || !mounted) return;
    final gen = ++_trailGeneration;
    setState(() {
      _trailLoading = true;
      _trailError = null;
    });
    try {
      final latPad = (bounds.north - bounds.south).abs() * 0.25;
      final lonPad = (bounds.east - bounds.west).abs() * 0.25;
      // Always fetch every type — the season only decides which are
      // emphasized, since filtering to ski tracks in winter would
      // hide every registered foot route.
      final fetched = await TurrutebaseService().fetchInBounds(
        bounds.south - latPad,
        bounds.west - lonPad,
        bounds.north + latPad,
        bounds.east + lonPad,
        TrailType.values.toSet(),
      );
      if (!mounted || gen != _trailGeneration) return;
      setState(() {
        _trails = fetched;
        _seasonalTypes = TurrutebaseService.seasonalTypes(
          DateTime.now(),
          _trip?.season,
        );
        _trailFetchedBounds = LatLngBounds(
          LatLng(bounds.south - latPad, bounds.west - lonPad),
          LatLng(bounds.north + latPad, bounds.east + lonPad),
        );
      });
    } on ServiceException catch (e) {
      if (!mounted || gen != _trailGeneration) return;
      setState(() => _trailError = e.message);
    } catch (_) {
      if (mounted && gen == _trailGeneration) {
        setState(() => _trailError = 'Rutedata kunne ikke leses. Prøv igjen.');
      }
    } finally {
      if (mounted && gen == _trailGeneration) {
        setState(() => _trailLoading = false);
      }
    }
  }

  Color _trailColor(TrailType type) => switch (type) {
    TrailType.ski => const Color(0xFF2E6FD8),
    TrailType.foot => NkColors.forestGreen,
    TrailType.bike => const Color(0xFFB45A1B),
    TrailType.other => NkColors.textSecondary,
  };

  bool _usablePosition(Position position) {
    final age = DateTime.now().difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        position.accuracy.isFinite &&
        position.accuracy > 0 &&
        position.accuracy <= 1000 &&
        age <= const Duration(minutes: 2) &&
        age >= const Duration(minutes: -1);
  }

  Future<void> _locateUser() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          nkToast(context, 'Gi appen posisjonstilgang i systeminnstillingene.');
        }
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          nkToast(context, 'Slå på posisjonstjenester i systeminnstillingene.');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      if (!_usablePosition(position)) {
        nkToast(
          context,
          'Posisjonstjenesten ga en gammel eller for unøyaktig posisjon. '
          'Kartet er ikke flyttet. Søk etter stedet ditt i stedet.',
        );
        return;
      }
      setState(
        () => _userLatLng = LatLng(position.latitude, position.longitude),
      );
      _mapCtrl.move(_userLatLng!, 13);
      nkToast(
        context,
        'Rapportert posisjon: nøyaktighet cirka ${position.accuracy.round()} meter. '
        'Dette er ikke en garanti for riktig plassering.',
      );
    } catch (_) {
      if (mounted) {
        nkToast(
          context,
          'Fant ikke posisjonen. Sjekk GPS og posisjonstilgang.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<Trip> _ensureTrip() async {
    final state = context.read<AppState>();
    return state.currentTrip ?? await state.createTrip();
  }

  void _loadFromTrip() {
    final trip = _trip;
    if (trip == null) {
      if (_anchorsFromTripId != null) {
        _anchorsFromTripId = null;
        _anchors.clear();
        _routeDirty = false;
        _results = [];
      }
      return;
    }
    if (_anchorsFromTripId == trip.id) return;
    // Trip changed — always reset working state so nothing leaks
    // over from the previous trip.
    _anchorsFromTripId = trip.id;
    _anchors
      ..clear()
      ..addAll(trip.route?.waypoints ?? const []);
    _results = [];
    final points = trip.route?.latLngs;
    if (widget.highlight == null && points != null && points.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _trip?.id == trip.id) {
          _mapCtrl.fitCamera(
            CameraFit.coordinates(
              coordinates: points,
              padding: _routeFitPadding,
            ),
          );
        }
      });
    }
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      // Move mode wins over tap modes — the tap repositions the
      // selected waypoint instead of adding a new one.
      if (_moveId != null) {
        final idx = _anchors.indexWhere((w) => w.id == _moveId);
        if (idx >= 0) {
          _anchors[idx]
            ..lat = point.latitude
            ..lon = point.longitude;
          _routeDirty = true;
          _results = [];
          _moveId = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              nkToast(context, 'Punktet er flyttet – beregn ruten på nytt');
            }
          });
        } else {
          _moveId = null;
        }
        return;
      }
      switch (_tapMode) {
        case _TapMode.start:
          _setAnchor(WaypointType.start, point);
          _tapMode = _TapMode.auto;
        case _TapMode.end:
          _setAnchor(WaypointType.end, point);
          _tapMode = _TapMode.auto;
        case _TapMode.waypoint:
          _insertWaypoint(point);
        case _TapMode.direct:
          _insertWaypoint(point, straightLeg: true);
          if (!_directHintShown) {
            _directHintShown = true;
            nkToast(
              context,
              'Punkt lagt til – strekningen hit tegnes som rett linje (estimat)',
            );
          }
        case _TapMode.auto:
          if (!_hasType(WaypointType.start)) {
            _setAnchor(WaypointType.start, point);
          } else if (!_hasType(WaypointType.end)) {
            _setAnchor(WaypointType.end, point);
          } else {
            _insertWaypoint(point);
          }
      }
      _results = [];
      _routeDirty = true;
    });
  }

  bool _hasType(WaypointType t) => _anchors.any((w) => w.type == t);

  /// Enters move mode for [w] — the next map tap repositions it.
  /// Triggered by long-press on the marker or the row's move icon.
  void _startMove(Waypoint w) {
    setState(() => _moveId = w.id);
    nkToast(context, 'Flyttemodus: trykk på kartet for å plassere «${w.name}»');
  }

  void _setAnchor(WaypointType type, LatLng point, {String? name}) {
    _anchors.removeWhere((w) => w.type == type);
    final label =
        name ??
        (type == WaypointType.start
            ? 'Start (A)'
            : type == WaypointType.end
            ? 'Mål (B)'
            : 'Punkt');
    final w = Waypoint(
      id: const Uuid().v4().substring(0, 8),
      name: label,
      lat: point.latitude,
      lon: point.longitude,
      type: type,
    );
    // Keep ordering: start, waypoints/overnight, end.
    if (type == WaypointType.start) {
      _anchors.insert(0, w);
    } else {
      _anchors.add(w);
    }
    if (name == null) _lookupName(w);
  }

  /// Replaces the generic «Start (A)»/«Mål (B)» label with the nearest
  /// place name, unless the user moved or renamed the point meanwhile.
  void _lookupName(Waypoint w) {
    final fallback = w.name;
    final lat = w.lat;
    final lon = w.lon;
    late final Future<void> job;
    job = context
        .read<AppState>()
        .geocodingService
        .reverse(w.latLng)
        .then((name) async {
          if (!mounted || name == null) return;
          if (w.name != fallback || w.lat != lat || w.lon != lon) return;
          setState(() => w.name = name);
          await _persistLateName(w);
        })
        .catchError((Object _) {})
        .whenComplete(() => _nameLookups.remove(job));
    _nameLookups.add(job);
  }

  /// A place name that arrives after the route was saved must still be
  /// stored, and can still give an unnamed trip its name.
  Future<void> _persistLateName(Waypoint w) async {
    final trip = _trip;
    final waypoints = trip?.route?.waypoints;
    if (trip == null ||
        waypoints == null ||
        !waypoints.any((x) => identical(x, w))) {
      return;
    }
    if (trip.name.trim().isEmpty) {
      final suggested = suggestTripName(waypoints);
      if (suggested.isNotEmpty) trip.name = suggested;
    }
    await context.read<AppState>().saveTrip(trip);
  }

  void _insertWaypoint(
    LatLng point, {
    String? name,
    bool straightLeg = false,
    WaypointType type = WaypointType.waypoint,
  }) {
    final endIdx = _anchors.indexWhere((w) => w.type == WaypointType.end);
    final w = Waypoint(
      id: const Uuid().v4().substring(0, 8),
      name:
          name ??
          (type == WaypointType.overnight
              ? 'Overnatting'
              : 'Via-punkt ${_anchors.length}'),
      lat: point.latitude,
      lon: point.longitude,
      type: type,
      straightLeg: straightLeg,
    );
    if (endIdx >= 0) {
      _anchors.insert(endIdx, w);
    } else {
      _anchors.add(w);
    }
  }

  Future<void> _calculateRoute() async {
    final state = context.read<AppState>();
    if (_anchors.length < 2 || state.busy) return;
    final anchors = List<Waypoint>.of(_anchors);
    // A trip whose start and goal sit on top of each other makes no
    // sense (0,0 km) — a round trip needs at least one via point.
    final start = anchors.firstWhere(
      (w) => w.type == WaypointType.start,
      orElse: () => anchors.first,
    );
    final end = anchors.lastWhere(
      (w) => w.type == WaypointType.end,
      orElse: () => anchors.last,
    );
    final hasVia = anchors.any(
      (w) => w.type != WaypointType.start && w.type != WaypointType.end,
    );
    if (!hasVia && const Distance()(start.latLng, end.latLng) < 30) {
      nkToast(
        context,
        'Start og mål er samme sted – velg et mål et annet sted, '
        'eller legg til via-punkter for en rundtur.',
      );
      return;
    }
    final trip = await _ensureTrip();
    if (!mounted) return;
    // Creating the first draft notifies listeners and can reset the
    // working anchors. Restore the user's unsaved map choices.
    _anchors
      ..clear()
      ..addAll(anchors);
    _anchorsFromTripId = trip.id;
    final oldRoute = trip.route;
    await state.buildRoute(
      trip,
      anchors.map((w) => w.latLng).toList(),
      waypoints: anchors,
    );
    if (!mounted) return;
    if (identical(oldRoute, trip.route) || trip.route?.hasRoute != true) {
      nkToast(
        context,
        state.lastError ?? 'Kunne ikke beregne ruten. Prøv igjen.',
      );
      return;
    }
    if (state.lastError != null) nkToast(context, state.lastError!);
    // The route was just computed - it is not out of date.
    setState(() => _routeDirty = false);
    if (trip.name.trim().isEmpty) {
      await Future.wait(_nameLookups)
          .timeout(const Duration(seconds: 4), onTimeout: () => <void>[]);
      final name = suggestTripName(anchors);
      if (name.isNotEmpty) {
        trip.name = name;
        await state.saveTrip(trip);
      }
      if (!mounted) return;
    }
    // Zoom to the computed route so the result is immediately visible.
    final pts = trip.route?.latLngs;
    if (pts != null && pts.length >= 2) {
      _mapCtrl.fitCamera(
        CameraFit.coordinates(coordinates: pts, padding: _routeFitPadding),
      );
    }
    await state.fetchElevation(trip);
    if (mounted && state.lastError != null) nkToast(context, state.lastError!);
    await state.reanalyze(trip);
    if (mounted) setState(() => _routeDirty = false);
  }

  Future<void> _clearRoute() async {
    final trip = _trip;
    if (trip?.route?.hasRoute == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tøm ruten?'),
          content: const Text(
            'Den lagrede ruten, høydeprofilen og rutebaserte forhold fjernes. '
            'Egne pakkegjenstander og måltider beholdes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Tøm rute'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      _anchors.clear();
      _results = [];
      _routeDirty = false;
    });
    if (trip != null) {
      await context.read<AppState>().clearRoute(trip);
    }
  }

  void _scheduleSearch(String q) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _results = [];
      _searchError = null;
      _searching = q.trim().length >= 2;
    });
    if (!_searching) return;
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _search(q, generation),
    );
  }

  Future<void> _search(String q, int generation) async {
    if (!mounted || generation != _searchGeneration) return;
    setState(() => _searching = true);
    try {
      final res = await context.read<AppState>().geocodingService.search(q);
      if (mounted && generation == _searchGeneration) {
        setState(() => _results = res);
      }
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(
          () => _searchError =
              'Stedssøket er utilgjengelig. Sjekk nettet og prøv igjen.',
        );
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  void _usePlace(PlaceResult p) {
    setState(() {
      if (!_hasType(WaypointType.start)) {
        _setAnchor(WaypointType.start, p.point, name: p.name);
      } else if (!_hasType(WaypointType.end)) {
        _setAnchor(WaypointType.end, p.point, name: p.name);
      } else {
        _insertWaypoint(p.point, name: p.name);
      }
      _results = [];
      _searchGeneration++;
      _debounce?.cancel();
      _searchError = null;
      _searching = false;
      _searchCtrl.clear();
    });
    _mapCtrl.move(p.point, 12);
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, Object>(
      (s) => (
        s.currentTripId,
        s.currentTrip?.route,
        s.currentTrip?.stages,
        s.currentTrip?.name,
        s.currentTrip?.activity,
        s.currentTrip?.season,
        s.busy,
      ),
    );
    final trip = context.read<AppState>().currentTrip;
    final wide = context.isWide;

    final map = _buildMap(trip);
    final panel = _buildPanel(trip);

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(flex: 3, child: map),
              VerticalDivider(width: 1, color: NkColors.border),
              SizedBox(width: 380, child: panel),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, constraints) => Stack(
            children: [
              Positioned.fill(bottom: constraints.maxHeight * 0.22, child: map),
              DraggableScrollableSheet(
                initialChildSize: 0.22,
                minChildSize: 0.22,
                maxChildSize: 0.86,
                builder: (_, controller) => Material(
                  elevation: 8,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildPanel(trip, scrollController: controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap(Trip? trip) {
    final route = trip?.route;
    final center =
        widget.highlight ??
        (_anchors.isNotEmpty
            ? _anchors.first.latLng
            : (route?.start ?? const LatLng(60.5, 8.5))); // Hardangervidda-ish

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: center,
            // Default view is zoom 7 — inside the Kartverket-topo
            // range so the automatic choice starts on the official
            // Norwegian map, not the world-overview fallback.
            initialZoom: widget.highlight != null
                ? 13
                : (_anchors.isNotEmpty ? 11 : 7),
            onTap: _onMapTap,
            onPositionChanged: _onCameraMoved,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: _mapSettings.baseForZoom(
                _mapZoom ??
                    (widget.highlight != null || _anchors.isNotEmpty ? 11 : 7),
              ),
              tileProvider: PersistentTileProvider(),
              userAgentPackageName: 'ai.norgeskompasset.app',
              maxZoom: 19,
            ),
            if (_skiOverlay)
              TileLayer(
                urlTemplate: _openSnowMap,
                tileProvider: PersistentTileProvider(),
                userAgentPackageName: 'ai.norgeskompasset.app',
              ),
            // Registered trails are a visual reference layer only —
            // taps on the map always place waypoints.
            if (_trailLayer && _trails.isNotEmpty)
              PolylineLayer<TrailRoute>(
                polylines: [
                  for (final t in _trails)
                    Polyline<TrailRoute>(
                      points: t.latLngs,
                      color: _trailColor(t.type).withValues(
                        alpha: _seasonalTypes.contains(t.type) ? 0.6 : 0.3,
                      ),
                      strokeWidth: _seasonalTypes.contains(t.type) ? 3 : 2,
                    ),
                ],
              ),
            if (route?.hasRoute == true)
              PolylineLayer(polylines: routePolylines(route!)),
            MarkerLayer(
              markers: [
                for (final w in _anchors)
                  _marker(
                    w,
                    moving: w.id == _moveId,
                    onLongPress: () => _startMove(w),
                  ),
                if (route?.hasRoute == true && _anchors.isEmpty)
                  Marker(
                    point: route!.start!,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.flag,
                      color: NkColors.forestGreen,
                      size: 28,
                    ),
                  ),
                if (route?.hasRoute == true && _anchors.isEmpty)
                  Marker(
                    point: route!.end!,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.flag,
                      color: NkColors.dangerRed,
                      size: 28,
                    ),
                  ),
                if (widget.highlight != null)
                  Marker(
                    point: widget.highlight!,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NkColors.primaryBlue.withValues(alpha: 0.18),
                        border: Border.all(
                          color: NkColors.primaryBlue,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: NkColors.primaryBlue,
                        size: 18,
                      ),
                    ),
                  ),
                if (_userLatLng != null)
                  Marker(
                    point: _userLatLng!,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NkColors.primaryBlue,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                const TextSourceAttribution(
                  '© Kartverket · © OpenStreetMap contributors · OpenTopoMap (CC-BY-SA)',
                ),
                if (_skiOverlay)
                  const TextSourceAttribution(
                    'OpenSnowMap · kartlagte løyper, ikke prepareringsstatus',
                  ),
              ],
            ),
          ],
        ),
        if (_trailLayer)
          Positioned(
            left: 10,
            right: 70,
            top: 64,
            child: Material(
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _trailLoading
                          ? 'Henter turruter …'
                          : _trailError ??
                                (_mapCtrl.camera.zoom < 8
                                    ? 'Zoom inn for å se turruter'
                                    : _trails.isEmpty
                                    ? 'Ingen registrerte ruter her — dekningen i Turrutebasen varierer'
                                    : '${_trails.length} ruter · Kartverket (NLOD)'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_trailError != null)
                      TextButton(
                        onPressed: () =>
                            _fetchTrails(_mapCtrl.camera.visibleBounds),
                        child: const Text('Prøv igjen'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        // Search + mode overlay
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Column(
            children: [
              NkCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Søk sted, fjell eller utgangspunkt…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Tøm søk',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _scheduleSearch('');
                            },
                          )
                        : null,
                  ),
                  onChanged: _scheduleSearch,
                ),
              ),
              if (_searchError != null)
                NkCard(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(child: Text(_searchError!)),
                      TextButton(
                        onPressed: () => _scheduleSearch(_searchCtrl.text),
                        child: const Text('Prøv igjen'),
                      ),
                    ],
                  ),
                ),
              if (_results.isNotEmpty)
                NkCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final p in _results)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 18),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => _usePlace(p),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Tap-mode chips — horizontal, scrollable so they never cover
        // more than one row of the map (important on small screens).
        // The row now spans the full bottom edge — the layer selector
        // moved up into the right-hand button column.
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _modeChip('Auto', _TapMode.auto, Icons.touch_app),
                const SizedBox(width: 6),
                _modeChip('Start (A)', _TapMode.start, Icons.play_arrow),
                const SizedBox(width: 6),
                _modeChip('Mål (B)', _TapMode.end, Icons.flag),
                const SizedBox(width: 6),
                ActionChip(
                  label: Text(_showAdvanced ? 'Færre valg' : 'Flere punktvalg'),
                  onPressed: () => setState(() {
                    _showAdvanced = !_showAdvanced;
                    if (!_showAdvanced &&
                        (_tapMode == _TapMode.waypoint ||
                            _tapMode == _TapMode.direct)) {
                      _tapMode = _TapMode.auto;
                    }
                  }),
                ),
                if (_showAdvanced) ...[
                  const SizedBox(width: 6),
                  _modeChip(
                    'Via-punkt · følg sti',
                    _TapMode.waypoint,
                    Icons.add_location_alt_outlined,
                  ),
                  const SizedBox(width: 6),
                  _modeChip(
                    'Rett linje · estimat',
                    _TapMode.direct,
                    Icons.timeline_outlined,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Move-mode banner — sits just above the mode chips so the
        // active placement state can't be missed.
        if (_moveId != null)
          Positioned(
            left: 10,
            right: 56,
            bottom: 52,
            child: NkCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: NkColors.warningAmber.withValues(alpha: 0.12),
              child: Row(
                children: [
                  const Icon(
                    Icons.open_with,
                    size: 16,
                    color: NkColors.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Trykk på kartet for å flytte punktet',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => setState(() => _moveId = null),
                    child: const Text('Avbryt', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          right: 10,
          top: 70,
          bottom: 70,
          child: SingleChildScrollView(
            reverse: true,
            child: Column(
              children: [
                // Layer selector — base maps plus the ski-trail overlay,
                // all layer control behind one button.
                PopupMenuButton<String>(
                  tooltip: 'Kartlag',
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: NkColors.border),
                    ),
                    child: const Icon(
                      Icons.layers_outlined,
                      size: 20,
                      color: NkColors.primaryBlue,
                    ),
                  ),
                  onSelected: (v) {
                    if (v == 'automatic') {
                      setState(_mapSettings.reset);
                    } else if (v == 'ski-overlay') {
                      setState(() => _mapSettings.skiOverride = !_skiOverlay);
                    } else if (v == 'turinfo') {
                      setState(() {
                        final on = !_trailLayer;
                        _trailLayer = on;
                        if (!on) {
                          _trails = [];
                          _trailFetchedBounds = null;
                        } else {
                          _trailDebounce?.cancel();
                          _trailDebounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (!mounted) return;
                              if (_mapCtrl.camera.zoom < 8) {
                                nkToast(
                                  context,
                                  'Zoom litt nærmere — ruter hentes per kartutsnitt',
                                );
                              }
                              _onCameraMoved(_mapCtrl.camera, false);
                            },
                          );
                        }
                      });
                    } else {
                      setState(() => _mapSettings.baseOverride = v);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Text(
                        'Viser: ${_mapSettings.activeBaseLabel(_mapZoom ?? 7)}'
                        '${_mapSettings.baseOverride == null ? ' (auto)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: NkColors.textSecondary,
                        ),
                      ),
                    ),
                    CheckedPopupMenuItem(
                      value: 'automatic',
                      checked: _mapSettings.automatic,
                      child: const Text('Automatisk kartvalg'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _kartverketTopo,
                      child: Text('Kartverket topo'),
                    ),
                    const PopupMenuItem(
                      value: _openTopoMap,
                      child: Text('OpenTopoMap'),
                    ),
                    const PopupMenuItem(
                      value: _osm,
                      child: Text('OpenStreetMap'),
                    ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: 'ski-overlay',
                      checked: _skiOverlay,
                      child: const Text('Skiløyper · ikke prepareringsstatus'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'turinfo',
                      checked: _trailLayer,
                      child: const Text('Registrerte stier (Kartverket)'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _mapButton(
                  Icons.my_location,
                  _locateUser,
                  tooltip: _locating ? 'Henter posisjon' : 'Min posisjon',
                ),
                const SizedBox(height: 6),
                // Pinch-zoom exists on touch devices — the +/- buttons only
                // earn their space on desktop/web.
                if (!_isTouchPlatform) ...[
                  _mapButton(Icons.add, () {
                    _mapCtrl.move(
                      _mapCtrl.camera.center,
                      _mapCtrl.camera.zoom + 1,
                    );
                  }, tooltip: 'Zoom inn'),
                  const SizedBox(height: 6),
                  _mapButton(Icons.remove, () {
                    _mapCtrl.move(
                      _mapCtrl.camera.center,
                      _mapCtrl.camera.zoom - 1,
                    );
                  }, tooltip: 'Zoom ut'),
                  const SizedBox(height: 6),
                ],
                _mapButton(Icons.fit_screen, () async {
                  // Fits the camera to the computed route.
                  if (route?.hasRoute == true) {
                    _mapCtrl.fitCamera(
                      CameraFit.coordinates(
                        coordinates: route!.latLngs,
                        padding: _routeFitPadding,
                      ),
                    );
                  }
                }, tooltip: 'Vis hele ruten'),
                const SizedBox(height: 6),
                // Loop generator — a route from the start anchor and
                // back. Second tap on the refresh icon rerolls a variant.
                if (_showAdvanced) ...[
                  _mapButton(
                    Icons.loop,
                    _loopDialog,
                    tooltip: 'Generer rundtur fra startpunkt',
                  ),
                ],
                if (_showAdvanced && _loopGenerated) ...[
                  const SizedBox(height: 6),
                  _mapButton(
                    Icons.refresh,
                    () => _generateLoop(reroll: true),
                    tooltip: 'Ny rundtur-variant',
                  ),
                ],
                if (_anchors.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _mapButton(Icons.undo, () {
                    // Quick undo for the most recent anchor — faster than
                    // finding the row in the waypoint list.
                    setState(() {
                      _anchors.removeLast();
                      _routeDirty = true;
                    });
                  }, tooltip: 'Angre siste punkt'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeChip(String label, _TapMode mode, IconData icon) {
    final active = _tapMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tapMode = active ? _TapMode.auto : mode;
          _directHintShown = false;
        });
        if (!active && mode == _TapMode.waypoint) {
          nkToast(
            context,
            'Via-punkt: ruten forsøker å følge kjente stier via punktet. Manglende forbindelse merkes som estimert rett linje.',
          );
        } else if (!active && mode == _TapMode.direct) {
          nkToast(
            context,
            'Rett linje fra forrige punkt: ingen stiberegning eller kontroll av fremkommelighet. Strekningen er et estimat.',
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? NkColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? NkColors.primaryBlue : NkColors.border,
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? Colors.white : NkColors.primaryBlue,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : NkColors.primaryBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapButton(
    IconData icon,
    VoidCallback onTap, {
    required String tooltip,
    bool active = false,
  }) {
    return Semantics(
      button: true,
      selected: active,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: active
            ? NkColors.primaryBlue.withValues(alpha: 0.12)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? NkColors.primaryBlue : NkColors.border,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Icon(icon, size: 20, color: NkColors.primaryBlue),
            ),
          ),
        ),
      ),
    );
  }

  // ── Side/bottom panel ──────────────────────────────────────

  Widget _buildPanel(Trip? trip, {ScrollController? scrollController}) {
    if (trip == null) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Start en ny tur',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Text(
            !_hasType(WaypointType.start)
                ? '1. Trykk i kartet eller søk etter et sted for å velge start.'
                : !_hasType(WaypointType.end)
                ? '2. Trykk i kartet der turen skal ende.'
                : '3. Klar! Trykk «Generer tur» for å beregne ruten.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          FilledButton.icon(
            onPressed: _anchors.length >= 2 && !context.read<AppState>().busy
                ? _calculateRoute
                : null,
            icon: const Icon(Icons.route),
            label: const Text('Generer tur'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              context.read<NavController>().openMapExplore();
            },
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('Finn turforslag'),
          ),
        ],
      );
    }
    final route = trip.route;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      children: [
        if (!context.isWide)
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: NkColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        Text(
          trip.name.isEmpty ? 'Tur uten navn' : trip.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        Text(
          '${trip.activity.label} · ${trip.season.label} · ${fmtCount(trip.hikingDays, 'dag', 'dager')}',
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.read<NavController>().openMapExplore(),
                icon: const Icon(Icons.travel_explore_outlined, size: 16),
                label: const Text('Finn turforslag'),
              ),
            ),
            IconButton(
              icon: Icon(_showConfig ? Icons.tune : Icons.tune_outlined),
              color: _showConfig
                  ? NkColors.primaryBlue
                  : NkColors.textSecondary,
              tooltip: 'Turinnstillinger',
              onPressed: () => setState(() => _showConfig = !_showConfig),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...[
          if (_showConfig) ...[
            _TripConfig(
              trip: trip,
              onSkiSelected: () => setState(() {}),
              onActivityChanged: () => setState(() => _routeDirty = true),
            ),
            const SizedBox(height: 12),
          ],
          if (_anchors.isNotEmpty) ...[
            _WaypointList(
              anchors: _anchors,
              onChanged: () => setState(() => _routeDirty = true),
              onMove: _startMove,
            ),
            const SizedBox(height: 12),
          ],
          if (_routeDirty && route?.hasRoute == true)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: NkColors.warningAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: NkColors.warningAmber.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.sync_problem_outlined,
                    size: 18,
                    color: NkColors.warningAmber,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Punkter eller aktivitet er endret. Ruten må beregnes på nytt. Trykk «Beregn rute».',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (route?.hasRoute == true) ...[
            _RouteSummary(trip: trip),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionBtn(
                icon: Icons.route,
                label: _anchors.length >= 2 ? 'Beregn rute' : 'Velg A og B',
                primary: true,
                enabled: _anchors.length >= 2 && !context.read<AppState>().busy,
                onTap: _calculateRoute,
              ),
              if (_showAdvanced) ...[
                _actionBtn(
                  icon: Icons.splitscreen_outlined,
                  label: 'Del inn i etapper',
                  enabled: route?.hasRoute == true,
                  onTap: () => _splitStages(trip),
                ),
                _actionBtn(
                  icon: Icons.delete_outline,
                  label: 'Tøm rute',
                  enabled: _anchors.isNotEmpty || route?.hasRoute == true,
                  onTap: _clearRoute,
                ),
              ],
              // Rarely-used file actions live in an overflow menu.
              PopupMenuButton<String>(
                tooltip: 'Flere valg',
                onSelected: (v) {
                  if (v == 'import') _importGpx();
                  if (v == 'export') _exportGpx(trip);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.upload_file_outlined),
                      title: Text('Importer GPX'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    enabled: route?.hasRoute == true,
                    child: const ListTile(
                      dense: true,
                      leading: Icon(Icons.download_outlined),
                      title: Text('Eksporter GPX'),
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: NkColors.primaryBlue),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: NkColors.primaryBlue,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Flere valg',
                        style: TextStyle(
                          fontSize: 12,
                          color: NkColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Everything autosaves on change — the only explicit action
          // left is moving on to the trip analysis.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: route?.hasRoute == true
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ElevationScreen(),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.terrain, size: 18),
              label: const Text('Til analyse'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Alt lagres automatisk. Grønn linje = beregnet rute fra kartdata, ikke bekreftet fremkommelighet. Oransje stiplet = estimert rett strekk.',
            style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
          ),
        ],
      ],
    );
  }

  /// Loop generator — builds two mid anchors rotated by [_loopSeed]
  /// around the start point, then runs the normal route calc so the
  /// loop follows real trails where possible.
  Future<void> _loopDialog() async {
    final start = _anchors
        .where((w) => w.type == WaypointType.start)
        .firstOrNull;
    if (start == null) {
      setState(() => _tapMode = _TapMode.start);
      nkToast(
        context,
        'Velg startpunkt først — trykk på kartet der turen skal starte.',
      );
      return;
    }
    final activity = _trip?.activity ?? TripActivity.foot;
    final km = await showDialog<double>(
      context: context,
      builder: (ctx) {
        var km = _loopKm;
        // Ski and bike trips often run longer than day hikes.
        final maxKm = switch (activity) {
          TripActivity.bike => 80.0,
          TripActivity.ski => 60.0,
          _ => 40.0,
        };
        km = km.clamp(5.0, maxKm);
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Generer rundtur'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lager en rundtur fra startpunktet på ca. ${km.round()} km. '
                  '${_surfaceText(activity)} Partier uten dekning vises som estimerte strekk.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Slider(
                  value: km.clamp(5.0, maxKm),
                  min: 5,
                  max: maxKm,
                  divisions: (maxKm - 5).round(),
                  label: '${km.round()} km',
                  onChanged: (v) => setD(() => km = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Avbryt'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, km),
                child: const Text('Generer'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || km == null) return;
    _loopKm = km;
    await _generateLoop();
  }

  static String _surfaceText(TripActivity a) => switch (a) {
    TripActivity.ski => 'Skilaget viser løyper, men ruteberegneren kan også velge veier og stier. Kontroller at forslaget følger ønsket skiløype.',
    TripActivity.bike => 'Ruten prøver å følge veier og sykkelstier.',
    TripActivity.paddle => 'Ruten prøver å følge vannveier.',
    _ => 'Ruten prøver å følge stier.',
  };

  Future<void> _generateLoop({bool reroll = false}) async {
    final start = _anchors
        .where((w) => w.type == WaypointType.start)
        .firstOrNull;
    if (start == null) return;
    if (reroll) _loopSeed++;
    final mids = loopAnchors(start.latLng, _loopKm, _loopSeed);
    setState(() {
      _anchors
        ..removeWhere((w) => w.type != WaypointType.start)
        ..addAll([
          for (var i = 0; i < mids.length; i++)
            Waypoint(
              id: const Uuid().v4(),
              name: 'Vendepunkt ${i + 1}',
              lat: mids[i].latitude,
              lon: mids[i].longitude,
              type: WaypointType.waypoint,
            ),
          Waypoint(
            id: const Uuid().v4(),
            name: 'Tilbake til start',
            lat: start.lat,
            lon: start.lon,
            type: WaypointType.end,
          ),
        ]);
      _loopGenerated = true;
      _routeDirty = true;
    });
    await _calculateRoute();
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    bool primary = false,
  }) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 16,
        color: enabled
            ? (primary ? NkColors.forestGreen : NkColors.primaryBlue)
            : NkColors.textSecondary,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary ? NkColors.forestGreen : NkColors.primaryBlue,
        side: BorderSide(
          color: enabled
              ? (primary ? NkColors.forestGreen : NkColors.primaryBlue)
              : NkColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Future<void> _exportGpx(Trip trip) async {
    try {
      final path = await GpxService.exportToDownloads(trip);
      if (mounted) nkToast(context, 'GPX lagret: $path');
    } on ServiceException {
      if (mounted) {
        nkToast(
          context,
          'GPX-eksport støttes ikke her – se Del tur-skjermen for å kopiere teksten.',
        );
      }
    }
  }

  Future<void> _importGpx() async {
    final state = context.read<AppState>();
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final parsed = GpxService.parse(utf8.decode(bytes));
      if (!mounted) return;
      final trip = await _ensureTrip();
      if (!mounted) return;
      await state.importRoute(trip, parsed.points, parsed.waypoints);
      if (!mounted) return;
      setState(() {
        _anchors
          ..clear()
          ..addAll(trip.route!.waypoints);
        _routeDirty = false;
      });
      _mapCtrl.fitCamera(
        CameraFit.coordinates(
          coordinates: trip.route!.latLngs,
          padding: _routeFitPadding,
        ),
      );
      await state.fetchElevation(trip);
      await state.reanalyze(trip);
      if (mounted) {
        nkToast(
          context,
          'GPX importert${parsed.name != null ? ' (${parsed.name})' : ''} – ${fmtKm(trip.route!.distanceMeters)}',
        );
      }
    } on ServiceException catch (e) {
      if (mounted) nkToast(context, e.message);
    } catch (_) {
      if (mounted) nkToast(context, 'Kunne ikke importere GPX-filen.');
    }
  }

  /// Lets the user pick the number of hiking days, then re-splits the
  /// route and shows the resulting stages. Days are derived from the
  /// trip dates, so the dialog adjusts start/end date when needed.
  Future<void> _splitStages(Trip trip) async {
    var days = trip.hikingDays.clamp(1, 14);
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Del inn i etapper'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ruten fordeles på ${fmtCount(days, 'dag', 'dager')}${trip.startDate == null ? ' – startdato settes til i dag' : ''}.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Periode: ${fmtDate(trip.startDate ?? DateTime.now())} → ${fmtDate((trip.startDate ?? DateTime.now()).add(Duration(days: days - 1)))}',
                style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Færre dager',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: days > 1 ? () => setD(() => days--) : null,
                  ),
                  Text(
                    '$days',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Flere dager',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: days < 14 ? () => setD(() => days++) : null,
                  ),
                ],
              ),
              Text(
                'Dager på tur',
                style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, days),
              child: const Text('Del inn'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final state = context.read<AppState>();
    trip.startDate ??= DateTime.now();
    trip.endDate = trip.startDate!.add(Duration(days: chosen - 1));
    await state.reanalyze(trip, datesChanged: true);
    if (!mounted) return;
    _showStages(trip);
  }

  /// Shows the resulting stage split in a bottom sheet.
  void _showStages(Trip trip) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text(
              'Etapper',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final s in trip.stages)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: NkColors.primaryBlue,
                  child: Text(
                    '${s.number}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                title: Text(
                  '${s.startName} → ${s.endName}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${fmtDate(s.date)} · ${fmtKm(s.distanceMeters)} · ~${fmtDuration(s.estimatedMinutes)}'
                  '${s.ascent > 0 ? ' · +${s.ascent.round()} m' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: s.difficulty != null
                    ? StatusPill(
                        s.difficulty!.level.label,
                        difficultyColor(s.difficulty!.level),
                      )
                    : null,
              ),
            const SizedBox(height: 8),
            Text(
              'Etappe-skille legges ved overnattingspunkter hvis de er markert – ellers fordeles dagene jevnt etter distanse.',
              style: TextStyle(
                fontSize: 11,
                color: NkColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Marker _marker(Waypoint w, {bool moving = false, VoidCallback? onLongPress}) {
  final (icon, color) = switch (w.type) {
    WaypointType.start => (Icons.play_arrow, NkColors.forestGreen),
    WaypointType.end => (Icons.flag, NkColors.dangerRed),
    WaypointType.overnight => (Icons.bed, NkColors.primaryBlue),
    WaypointType.waypoint => (Icons.circle, NkColors.warningAmber),
  };
  return Marker(
    point: w.latLng,
    width: 34,
    height: 40,
    child: GestureDetector(
      onLongPress: onLongPress,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: moving ? NkColors.warningAmber : Colors.white,
                width: moving ? 3 : 2,
              ),
            ),
            child: Icon(icon, size: 12, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

// ── Trip config ─────────────────────────────────────────────

class _TripConfig extends StatefulWidget {
  final Trip trip;

  /// Called when the user switches the trip to ski mode — the map
  /// screen turns on the ski-trail overlay so the planner sees the
  /// pistes while placing waypoints.
  final VoidCallback? onSkiSelected;
  final VoidCallback? onActivityChanged;
  const _TripConfig({
    required this.trip,
    this.onSkiSelected,
    this.onActivityChanged,
  });

  @override
  State<_TripConfig> createState() => _TripConfigState();
}

class _TripConfigState extends State<_TripConfig> {
  late TextEditingController _name;
  late TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.trip.name);
    _notes = TextEditingController(text: widget.trip.notes);
  }

  @override
  void didUpdateWidget(covariant _TripConfig old) {
    super.didUpdateWidget(old);
    if (old.trip.id != widget.trip.id) {
      _name.text = widget.trip.name;
      _notes.text = widget.trip.notes;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final trip = widget.trip;
    final state = context.read<AppState>();
    final initial =
        (start ? trip.startDate : trip.endDate) ??
        DateTime.now().add(const Duration(days: 14));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 540)),
      helpText: start ? 'Startdato' : 'Sluttdato',
    );
    if (picked == null || !mounted) return;
    var seasonChanged = false;
    setState(() {
      if (start) {
        // Moving the start keeps the number of days.
        final span = trip.startDate != null && trip.endDate != null
            ? trip.endDate!.difference(trip.startDate!)
            : Duration.zero;
        trip.startDate = picked;
        trip.endDate = picked.add(span.isNegative ? Duration.zero : span);
        // The packing rules follow the season, so keep it in step
        // with the chosen start date.
        final season = TurrutebaseService.seasonForDate(picked);
        if (season != trip.season) {
          seasonChanged = true;
          trip.season = season;
          if (season == TripSeason.winter &&
              trip.activity == TripActivity.paddle) {
            trip.activity = TripActivity.foot;
            trip.carry = CarryMode.backpack;
          }
        }
      } else {
        trip.endDate = picked.isBefore(trip.startDate ?? picked)
            ? trip.startDate
            : picked;
      }
    });
    if (seasonChanged) {
      nkToast(
        context,
        'Sesong satt til ${trip.season.label} ut fra startdatoen – '
        'pakkelisten er oppdatert.',
      );
    }
    await state.reanalyze(trip, datesChanged: true);
  }

  /// Asks once whether a ski trip crosses avalanche terrain, so the
  /// packing list can mark the avalanche trio correctly.
  Future<void> _askAvalancheTerrain(Trip trip) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Går turen i skredterreng?'),
        content: const Text(
          'Bratte fjellsider over ca. 30° eller under slike heng er '
          'skredterreng. Svaret avgjør om skredsøker, spade og søkestang '
          'blir påkrevd i pakkelisten. Sjekk alltid varsom.no.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vet ikke'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nei, løyper/flatt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja, mulig skred'),
          ),
        ],
      ),
    );
    if (answer != null) trip.avalancheTerrain = answer;
  }

  Future<void> _pickExpectedReturn() async {
    final trip = widget.trip;
    final state = context.read<AppState>();
    final day = await showDatePicker(
      context: context,
      initialDate: trip.expectedReturn ?? trip.endDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 540)),
      helpText: 'Hjemme senest – dato',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        trip.expectedReturn ?? day.add(const Duration(hours: 18)),
      ),
      helpText: 'Hjemme senest – klokkeslett',
    );
    if (time == null || !mounted) return;
    setState(() {
      trip.expectedReturn = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
    });
    await state.saveTrip(trip);
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final state = context.read<AppState>();
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Turinnstillinger', icon: Icons.tune),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Turnavn'),
            onChanged: (v) => trip.name = v,
            onEditingComplete: () => state.saveTrip(trip),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Startdato',
                  date: trip.startDate,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 8),
              // Duration has one source: start date + «Dager». The last
              // day is derived and shown read-only.
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Siste dag',
                    helperText: 'Endres med «Dager»',
                  ),
                  child: Text(
                    fmtDate(trip.endDate),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DateField(
            label: 'Hjemme senest (valgfritt)',
            date: trip.expectedReturn,
            text: trip.expectedReturn == null
                ? 'Ikke satt'
                : fmtDateTime(trip.expectedReturn!),
            onTap: _pickExpectedReturn,
          ),
          if (trip.expectedReturn != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() => trip.expectedReturn = null);
                  state.saveTrip(trip);
                },
                child: const Text('Fjern'),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TripActivity>(
                  key: ValueKey('act-${trip.activity.name}'),
                  initialValue: trip.activity,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aktivitet',
                    helperText: 'Ski viser løypelag; ruten må kontrolleres',
                  ),
                  items: [
                    for (final a in TripActivity.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() {
                      trip.activity = v;
                      switch (v) {
                        case TripActivity.ski:
                          if (trip.season == TripSeason.summer) {
                            trip.season = TripSeason.winter;
                          }
                          if (trip.carry == CarryMode.canoe) {
                            trip.carry = CarryMode.backpack;
                          }
                        case TripActivity.paddle:
                          trip.carry = CarryMode.canoe;
                          if (trip.season == TripSeason.winter) {
                            trip.season = TripSeason.summer;
                          }
                        // Paddling requires open water — can't stay
                        // on the winter season.

                        default:
                          if (trip.carry == CarryMode.canoe) {
                            trip.carry = CarryMode.backpack;
                          }
                      }
                    });
                    if (v == TripActivity.ski) widget.onSkiSelected?.call();
                    if (v == TripActivity.ski &&
                        trip.avalancheTerrain == null) {
                      await _askAvalancheTerrain(trip);
                    }
                    widget.onActivityChanged?.call();
                    await state.updateTripSetup(trip);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<HikingPace>(
                  initialValue: trip.pace,
                  decoration: const InputDecoration(labelText: 'Tempo'),
                  items: [
                    for (final p in HikingPace.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => trip.pace = v);
                    await state.reanalyze(trip);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AccommodationType>(
                  initialValue: trip.accommodation,
                  decoration: const InputDecoration(labelText: 'Overnatting'),
                  items: [
                    for (final a in AccommodationType.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => trip.accommodation = v);
                    await state.updateTripSetup(trip);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<TripSeason>(
                  key: ValueKey('season-${trip.season.name}'),
                  initialValue: trip.season,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sesong',
                    helperText: 'Settes fra startdatoen – kan overstyres',
                  ),
                  items: [
                    for (final s in TripSeason.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() {
                      trip.season = v;
                      // Winter allows foot (snowshoes) and ski trips;
                      // only paddling needs open water.
                      if (v == TripSeason.winter &&
                          trip.activity == TripActivity.paddle) {
                        trip.activity = TripActivity.foot;
                        trip.carry = CarryMode.backpack;
                      }
                    });
                    if (v == TripSeason.winter) {
                      widget.onSkiSelected?.call();
                    }
                    widget.onActivityChanged?.call();
                    await state.updateTripSetup(trip);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<CarryMode>(
                  key: ValueKey('carry-${trip.carry.name}'),
                  initialValue: trip.carry,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bæring'),
                  items: [
                    for (final c in CarryMode.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => trip.carry = v);
                    await state.updateTripSetup(trip);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Dager'),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Én dag kortere',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () async {
                          if ((trip.endDate != null &&
                              trip.startDate != null &&
                              trip.endDate!.isAfter(trip.startDate!))) {
                            setState(
                              () => trip.endDate = trip.endDate!.subtract(
                                const Duration(days: 1),
                              ),
                            );
                            await state.reanalyze(trip, datesChanged: true);
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          '${trip.hikingDays}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Én dag lengre',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () async {
                          final base =
                              trip.endDate ?? trip.startDate ?? DateTime.now();
                          setState(
                            () => trip.endDate = base.add(
                              const Duration(days: 1),
                            ),
                          );
                          trip.startDate ??= DateTime.now();
                          await state.reanalyze(trip, datesChanged: true);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Deltakere',
                    helperText: 'Skalerer matplan og pakkeliste',
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Færre deltakere',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () async {
                          if (trip.participants > 1) {
                            setState(() => trip.participants--);
                            await state.updateParticipants(trip);
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          '${trip.participants}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Flere deltakere',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () async {
                          if (trip.participants < 20) {
                            setState(() => trip.participants++);
                            await state.updateParticipants(trip);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (trip.activity == TripActivity.ski ||
              trip.season == TripSeason.winter ||
              trip.avalancheTerrain != null) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<bool?>(
              key: ValueKey('terrain-${trip.avalancheTerrain}'),
              initialValue: trip.avalancheTerrain,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Skredterreng',
                helperText: 'Styrer skredutstyr – sjekk varsom.no ved tvil',
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Ukjent')),
                DropdownMenuItem(
                  value: false,
                  child: Text('Utenfor skredterreng'),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text('Mulig skredterreng'),
                ),
              ],
              onChanged: (v) async {
                setState(() => trip.avalancheTerrain = v);
                await state.updateTripSetup(trip);
              },
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notater (valgfritt)',
              hintText: 'Erfaring, utstyr, avtaler…',
            ),
            onChanged: (v) => trip.notes = v,
            onEditingComplete: () => state.saveTrip(trip),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String? text;
  final VoidCallback onTap;
  const _DateField({
    required this.label,
    required this.date,
    this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(
          text ?? fmtDate(date),
          style: TextStyle(
            fontSize: 13,
            color: date == null ? NkColors.textSecondary : NkColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Waypoint list ───────────────────────────────────────────

class _WaypointList extends StatelessWidget {
  final List<Waypoint> anchors;
  final VoidCallback onChanged;

  /// Asks the parent to enter move mode for the waypoint — the next
  /// map tap then repositions it.
  final void Function(Waypoint)? onMove;
  const _WaypointList({
    required this.anchors,
    required this.onChanged,
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    // Start (first) and end (last) keep their semantic positions; the
    // middle waypoints are drag-reorderable.
    final firstIsStart =
        anchors.isNotEmpty && anchors.first.type == WaypointType.start;
    final lastIsEnd =
        anchors.length > (firstIsStart ? 1 : 0) &&
        anchors.last.type == WaypointType.end;
    final midStart = firstIsStart ? 1 : 0;
    final midEnd = anchors.length - (lastIsEnd ? 1 : 0);

    Widget row(int i) => _WaypointRow(
      key: ValueKey(anchors[i].id),
      waypoint: anchors[i],
      hasIncomingLeg: i > 0,
      onMove: onMove == null ? null : () => onMove!(anchors[i]),
      onChanged: onChanged,
      onRemove: () {
        anchors.removeAt(i);
        onChanged();
      },
    );

    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Rutepunkter', icon: Icons.alt_route),
          const SizedBox(height: 2),
          if (firstIsStart) row(0),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // onReorderItem: newIndex already accounts for the removal.
            onReorderItem: (oldI, newI) {
              final w = anchors.removeAt(midStart + oldI);
              anchors.insert(midStart + newI, w);
              onChanged();
            },
            children: [for (var i = midStart; i < midEnd; i++) row(i)],
          ),
          if (lastIsEnd) row(anchors.length - 1),
          if (midEnd > midStart)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Via-punkt følger sti når mulig. Linje-ikonet velger rett linje fra forrige punkt (estimat, uten kontroll av fremkommelighet). Dra for rekkefølge · seng = overnatting · kryss-piler = flytt',
                style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaypointRow extends StatelessWidget {
  final Waypoint waypoint;

  /// Whether a leg leads into this point (false for the first anchor).
  /// Controls visibility of the straight-leg toggle.
  final bool hasIncomingLeg;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// Enters move mode for this waypoint (next map tap repositions it).
  final VoidCallback? onMove;

  const _WaypointRow({
    super.key,
    required this.waypoint,
    required this.hasIncomingLeg,
    required this.onChanged,
    required this.onRemove,
    this.onMove,
  });

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: waypoint.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gi punktet navn'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'F.eks. Lunch ved vannet, Hytte…',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    if (name != null) {
      waypoint.name = name.trim();
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (waypoint.type) {
      WaypointType.start => (Icons.play_arrow, NkColors.forestGreen),
      WaypointType.end => (Icons.flag, NkColors.dangerRed),
      WaypointType.overnight => (Icons.bed, NkColors.primaryBlue),
      WaypointType.waypoint => (Icons.circle, NkColors.warningAmber),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _rename(context),
              child: Text(
                waypoint.name.isEmpty
                    ? '${waypoint.lat.toStringAsFixed(4)}, ${waypoint.lon.toStringAsFixed(4)}'
                    : waypoint.name,
                style: const TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (onMove != null)
            IconButton(
              tooltip: 'Flytt punktet – trykk deretter på kartet',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.open_with,
                size: 17,
                color: NkColors.textSecondary,
              ),
              onPressed: onMove,
            ),
          if (hasIncomingLeg)
            IconButton(
              tooltip: waypoint.straightLeg
                  ? 'Strekningen hit er rett linje – trykk for stiruting'
                  : 'Tegn strekningen hit som rett linje (estimat)',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                waypoint.straightLeg ? Icons.timeline : Icons.timeline_outlined,
                size: 17,
                color: waypoint.straightLeg
                    ? NkColors.warningAmber
                    : NkColors.textSecondary,
              ),
              onPressed: () {
                waypoint.straightLeg = !waypoint.straightLeg;
                onChanged();
              },
            ),
          if (waypoint.type == WaypointType.waypoint ||
              waypoint.type == WaypointType.overnight)
            IconButton(
              tooltip: waypoint.type == WaypointType.overnight
                  ? 'Gjør til vanlig punkt'
                  : 'Merk som overnatting',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                waypoint.type == WaypointType.overnight
                    ? Icons.bed
                    : Icons.bed_outlined,
                size: 17,
                color: waypoint.type == WaypointType.overnight
                    ? NkColors.primaryBlue
                    : NkColors.textSecondary,
              ),
              onPressed: () {
                waypoint.type = waypoint.type == WaypointType.overnight
                    ? WaypointType.waypoint
                    : WaypointType.overnight;
                onChanged();
              },
            ),
          IconButton(
            tooltip: 'Fjern punkt',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 17, color: NkColors.dangerRed),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ── Route summary ───────────────────────────────────────────

class _RouteSummary extends StatelessWidget {
  final Trip trip;
  const _RouteSummary({required this.trip});

  @override
  Widget build(BuildContext context) {
    final route = trip.route!;
    final totalTime = trip.totalEstimatedMinutes;
    final hardest = trip.stages.isEmpty
        ? null
        : trip.stages.reduce(
            (a, b) => (a.difficulty?.score ?? 0) >= (b.difficulty?.score ?? 0)
                ? a
                : b,
          );
    // Elevation tiles only carry real data once the elevation
    // fetch has run — before that, show an honest "not fetched"
    // state with a direct retry instead of misleading +0 m.
    final hasElevation = route.points.any((p) => p.elevation != null);
    final loadingElevation = context.select<AppState, bool>(
      (s) => s.busy && s.busyLabel == AppState.elevationBusyLabel,
    );
    final showElevation = hasElevation || loadingElevation;

    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  'Rutesammendrag',
                  icon: Icons.insights_outlined,
                ),
              ),
              StatusPill(
                switch (route.source) {
                  RouteSource.trail => 'Stirute',
                  RouteSource.mixed => 'Delvis estimert',
                  RouteSource.manual => 'Manuell',
                  RouteSource.estimated => 'Estimert',
                },
                route.source == RouteSource.trail
                    ? NkColors.forestGreen
                    : NkColors.warningAmber,
                icon: route.source == RouteSource.trail
                    ? Icons.verified_outlined
                    : Icons.help_outline,
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.1,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              InfoTile(
                'Distanse',
                fmtKm(route.distanceMeters),
                icon: Icons.route,
              ),
              InfoTile(
                'Estimert tid',
                totalTime > 0 ? fmtDuration(totalTime) : '–',
                icon: Icons.schedule,
              ),
              InfoTile(
                'Etapper',
                '${trip.stages.length}',
                icon: Icons.flag_outlined,
              ),
              if (showElevation)
                InfoTile(
                  'Stigning',
                  loadingElevation
                      ? 'Beregner…'
                      : '+${route.totalAscent.round()} m',
                  icon: Icons.trending_up,
                ),
              if (showElevation)
                InfoTile(
                  'Nedstigning',
                  loadingElevation
                      ? 'Beregner…'
                      : '−${route.totalDescent.round()} m',
                  icon: Icons.trending_down,
                ),
              if (showElevation)
                InfoTile(
                  'Høyeste punkt',
                  loadingElevation
                      ? 'Beregner…'
                      : fmtMeters(route.highestPoint),
                  icon: Icons.terrain,
                ),
            ],
          ),
          if (!showElevation) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.terrain, size: 15, color: NkColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Høydedata er ikke hentet for denne ruten.',
                    style: TextStyle(
                      fontSize: 12,
                      color: NkColors.textSecondary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      context.read<AppState>().fetchElevation(trip),
                  icon: const Icon(Icons.download_outlined, size: 15),
                  label: const Text(
                    'Hent høyder',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: NkColors.primaryBlue,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
          if (hardest?.difficulty != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Vanskeligste etappe: ',
                  style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
                ),
                StatusPill(
                  'Etappe ${hardest!.number} – ${hardest.difficulty!.level.label}',
                  difficultyColor(hardest.difficulty!.level),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            route.sourceLabel,
            style: TextStyle(
              fontSize: 11,
              color: NkColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
