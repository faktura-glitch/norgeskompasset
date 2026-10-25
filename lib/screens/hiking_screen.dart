import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/daylight.dart';
import '../core/format.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../services/tracking_controller.dart';
import '../models/trip.dart';
import '../services/tile_cache.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'elevation_screen.dart';
import 'review_screen.dart';
import 'safety_screen.dart';
import 'weather_screen.dart';

/// Simplified, high-contrast mode for use on the trail.
/// All trip data is read from local storage — works offline.
/// Map tiles and weather refresh require connectivity.
class HikingScreen extends StatefulWidget {
  const HikingScreen({super.key});

  @override
  State<HikingScreen> createState() => _HikingScreenState();
}

class _HikingScreenState extends State<HikingScreen> {
  StreamSubscription<CompassEvent>? _compassSub;
  Position? _position;
  double? _deviceHeading;
  bool _compassAccurate = true;
  // Heading-up mode: map rotates to match the smoothed bearing;
  // _mapHeading is the last rotation actually applied so manual
  // two-finger rotation can be detected and exits the mode.
  bool _headingUp = false;
  double _mapHeading = 0;
  String? _gpsMessage;
  bool _tracking = false;
  bool _gpsAccurate = true;
  final _mapCtrl = MapController();
  bool _showMap = true;
  bool _mapReady = false;

  bool _followUser = true;
  bool _tileFailed = false;
  String _mapUrl = TileCache.urlTemplate;
  bool _mapExpanded = false;

  // Off-route state mirrors TrackingController (which computes it
  // in the background so alerts also fire with the screen off).
  bool _offRoute = false;
  double? _deviationMeters;
  late final AppState _state;
  Trip? get _trackingTrip =>
      _state.trips.where((t) => t.id == _state.tracking.tripId).firstOrNull ??
      _state.currentTrip;

  @override
  void initState() {
    super.initState();
    // Captured in initState — context.read is not allowed in dispose.
    _state = context.read<AppState>();
    _state.tracking.addListener(_trackingChanged);
    _tracking = _state.tracking.isActive;
    _position = _state.tracking.position;
    _startCompass();
  }

  /// Device magnetometer → view-cone heading. Null/empty on
  /// platforms without a compass (web, desktop) — the marker then
  /// falls back to GPS course when moving.
  void _startCompass() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      _compassSub = FlutterCompass.events?.listen((e) {
        final h = e.heading;
        if (!mounted || h == null) return;
        // Low-pass the bearing — raw magnetometer jitters, and
        // rotating the map per tick would make it flutter.
        _deviceHeading = _deviceHeading == null
            ? h
            : _lerpAngle(_deviceHeading!, h, 0.25);
        _compassAccurate = (e.accuracy ?? 30) < 30;
        if (_headingUp && _showMap && _mapReady) {
          final diff = ((_deviceHeading! - _mapHeading + 540) % 360) - 180;
          // Re-rotate only past 5° drift — the map snaps to the
          // bearing in steps instead of wobbling continuously.
          if (diff.abs() > 5) {
            _mapHeading = _deviceHeading!;
            _mapCtrl.rotate(_mapHeading);
          }
        }
        setState(() {});
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Which way the user is facing: the magnetometer when it works,
  /// else the GPS course — but only once walking fast enough for a
  /// course-over-ground to be meaningful.
  double? _displayHeading(Position pos) =>
      _deviceHeading ??
      (pos.speed > 0.8 && pos.heading >= 0 ? pos.heading : null);

  /// Circular exponential smoothing between two bearings.
  static double _lerpAngle(double from, double to, double t) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return (from + d * t + 360) % 360;
  }

  /// North-up ⇄ heading-up. Heading-up needs a bearing source —
  /// without compass *and* without walking speed there is nothing
  /// to rotate toward, so we refuse instead of showing a frozen,
  /// misleading rotation.
  void _toggleHeadingUp() {
    final pos = _position;
    final src = pos != null ? _displayHeading(pos) : _deviceHeading;
    if (!_headingUp && src == null) {
      nkToast(
        context,
        'Kurs er ikke tilgjengelig ennå – vent på kompass eller begynn å gå.',
      );
      return;
    }
    setState(() {
      _headingUp = !_headingUp;
      _mapHeading = _headingUp ? src! : 0;
      _mapCtrl.rotate(_mapHeading);
    });
  }

  @override
  void dispose() {
    _state.tracking.removeListener(_trackingChanged);
    _compassSub?.cancel();
    // Flush any unsaved track points.
    unawaited(_state.tracking.flush().catchError((Object _) {}));
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _startTracking() async {
    final trip = _trackingTrip;
    if (trip != null) await _state.tracking.start(trip.id);
  }

  void _trackingChanged() {
    if (!mounted) return;
    final controller = _state.tracking;
    final pos = controller.position;
    setState(() {
      _tracking = controller.isActive;
      _position = pos;
      _gpsAccurate = pos != null && pos.accuracy <= 50;
      _gpsMessage = controller.error;
      _offRoute = controller.offRoute;
      _deviationMeters = controller.deviationMeters;
    });
    if (pos == null || !_tracking) return;
    if (_showMap && _mapReady && _followUser) {
      _mapCtrl.move(LatLng(pos.latitude, pos.longitude), _mapCtrl.camera.zoom);
    }
    // Heading-up without a compass: rotate on GPS course while
    // walking (desktop/web where the magnetometer is absent).
    if (_headingUp &&
        _showMap &&
        _mapReady &&
        _deviceHeading == null &&
        pos.speed > 0.8 &&
        pos.heading >= 0) {
      _mapHeading = pos.heading;
      _mapCtrl.rotate(_mapHeading);
    }
  }

  /// Ends hiking mode — offers to go straight to the trip review so
  /// the plan→hike→learn loop is closed while the hike is fresh.
  Future<void> _confirmExit(Trip trip) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avslutt turmodus?'),
        content: Text(
          'Sporet ditt (${trip.trackLog.length} punkter) lagres på turen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Fortsett turen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'exit'),
            child: const Text('Bare lukk'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'review'),
            child: const Text('Avslutt og evaluer'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;
    await _state.tracking.stop();
    if (!mounted || _state.tracking.phase == TrackingPhase.error) return;
    setState(() => _tracking = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pop(context);
      if (choice == 'review') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReviewScreen()),
        );
      }
    });
  }

  Future<void> _toggleTracking() async {
    if (_tracking || _state.tracking.phase == TrackingPhase.starting) {
      await _state.tracking.pause();
    } else if (!_state.tracking.isBusy) {
      await _startTracking();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, (String?, int)>(
      (s) => (s.currentTripId, s.trips.length),
    );
    final trip = _trackingTrip;
    final pos = _position;

    return PopScope(
      canPop: !_tracking && !_state.tracking.isBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && trip != null) _confirmExit(trip);
      },
      child: Scaffold(
        backgroundColor: NkColors.primaryBlueDark,
        body: SafeArea(
          child: trip == null
              ? Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Tilbake',
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.navigation_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Ingen aktiv tur',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Velg en tur og start turmodus fra turlisten.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          _TopBtn(
                            Icons.arrow_back,
                            'Tilbake',
                            () => Navigator.maybePop(context),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              trip.name.isEmpty ? 'Turmodus' : trip.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _TopBtn(
                            Icons.map_outlined,
                            _showMap ? 'Skjul kart' : 'Kart',
                            () => setState(() {
                              _mapReady = false;
                              _showMap = !_showMap;
                            }),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _tracking
                                ? Icons.fiber_manual_record
                                : Icons.pause_circle_outline,
                            color: _tracking
                                ? Colors.greenAccent
                                : Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _state.tracking.phase == TrackingPhase.starting
                                  ? 'Starter GPS … trykk Pause for å avbryte'
                                  : _state.tracking.phase ==
                                        TrackingPhase.stopping
                                  ? 'Lagrer og stopper …'
                                  : _tracking
                                  ? 'Sporing aktiv · ${trip.trackLog.length} punkter'
                                  : trip.trackLog.isEmpty
                                  ? 'Klar til å starte sporing'
                                  : 'Sporing pauset',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_gpsMessage != null)
                      Container(
                        width: double.infinity,
                        color: NkColors.warningAmber,
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _gpsMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: NkColors.textPrimary,
                          ),
                        ),
                      )
                    else if (pos != null && !_gpsAccurate)
                      Container(
                        width: double.infinity,
                        color: NkColors.warningAmber.withValues(alpha: 0.9),
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'Unøyaktig posisjon (±${pos.accuracy.round()} m)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: NkColors.textPrimary,
                          ),
                        ),
                      ),
                    if (_offRoute && _tracking)
                      Container(
                        width: double.infinity,
                        color: NkColors.dangerRed,
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Du ser ut til å være ute av ruten '
                                '(${(_deviationMeters ?? 0).round()} m) – sjekk kartet og kompasset.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_tracking &&
                        trip.expectedReturn != null &&
                        DateTime.now().isAfter(trip.expectedReturn!))
                      Container(
                        width: double.infinity,
                        color: NkColors.dangerRed,
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.alarm,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Du sa du skulle være hjemme innen '
                                '${fmtDateTime(trip.expectedReturn!)} – '
                                'gi beskjed til nødkontakten din.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_tracking &&
                        trip.route?.hasRoute == true &&
                        trip.route?.supportsDeviationAlerts != true)
                      Container(
                        width: double.infinity,
                        color: NkColors.warningAmber.withValues(alpha: 0.9),
                        padding: const EdgeInsets.all(8),
                        child: const Text(
                          'Ruten har ikke et fullstendig beregnet stispor – '
                          'avviksvarsling er avslått.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_showMap)
                      _mapExpanded
                          ? Expanded(child: _buildMap(trip))
                          : SizedBox(height: 240, child: _buildMap(trip)),
                    if (!(_showMap && _mapExpanded))
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _ProgressCard(trip: trip, position: pos),
                              const SizedBox(height: 12),
                              _StageCard(trip: trip, position: pos),
                              const SizedBox(height: 12),
                              _AltCard(trip: trip, position: pos),
                            ],
                          ),
                        ),
                      ),
                    // Quick actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          _ActionBtn(
                            icon: _tracking ? Icons.pause : Icons.play_arrow,
                            label:
                                _state.tracking.phase == TrackingPhase.starting
                                ? 'Pause'
                                : _tracking
                                ? 'Pause'
                                : trip.trackLog.isEmpty
                                ? 'Start'
                                : 'Fortsett',
                            onTap: _toggleTracking,
                          ),
                          _ActionBtn(
                            icon: Icons.cloud_outlined,
                            label: 'Vær',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WeatherScreen(),
                              ),
                            ),
                          ),
                          _ActionBtn(
                            icon: Icons.terrain,
                            label: 'Høyde',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ElevationScreen(),
                              ),
                            ),
                          ),
                          _ActionBtn(
                            icon: Icons.emergency_outlined,
                            label: 'Nødinfo',
                            alert: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SafetyScreen(emergencyFirst: true),
                              ),
                            ),
                          ),
                          _ActionBtn(
                            icon: Icons.close,
                            label: 'Avslutt',
                            onTap: () => _confirmExit(trip),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildMap(Trip trip) {
    final route = trip.route;
    final pos = _position;
    final heading = pos != null ? _displayHeading(pos) : null;
    final center = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : (route?.start ?? const LatLng(60.5, 8.5));
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            onMapReady: () => _mapReady = true,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _followUser) {
                setState(() => _followUser = false);
              }
              // A deliberate two-finger rotation exits heading-up —
              // the user took manual control of the bearing.
              if (hasGesture &&
                  _headingUp &&
                  (camera.rotation - _mapHeading).abs() > 2) {
                setState(() => _headingUp = false);
              }
            },
          ),
          children: [
            TileLayer(
              key: ValueKey(_mapUrl),
              urlTemplate: _mapUrl,
              errorTileCallback: (_, _, _) {
                if (!mounted || _tileFailed) return;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _tileFailed = true);
                });
              },
              tileProvider: PersistentTileProvider(),
              userAgentPackageName: 'ai.norgeskompasset.app',
            ),
            if (route?.hasRoute == true)
              PolylineLayer(polylines: routePolylines(route!)),
            // Recorded track — what you have actually walked.
            if (trip.trackLog.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      for (final t in trip.trackLog) LatLng(t.lat, t.lon),
                    ],
                    strokeWidth: 3,
                    color: const Color(0xFF4FC3F7),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (pos != null) ...[
                  if (heading != null)
                    // View cone — device compass bearing, or GPS
                    // course when walking. Painted below the dot.
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 130,
                      height: 130,
                      child: Transform.rotate(
                        angle:
                            (heading - _mapCtrl.camera.rotation) *
                            math.pi /
                            180,
                        child: CustomPaint(
                          painter: _HeadingCone(
                            color: _gpsAccurate
                                ? NkColors.primaryBlue
                                : NkColors.warningAmber,
                            // Faded cone = compass needs calibration
                            // (figure-8 wiggle) — don't trust it fully.
                            alpha: _compassAccurate || _deviceHeading == null
                                ? 1.0
                                : 0.45,
                          ),
                        ),
                      ),
                    ),
                  Marker(
                    point: LatLng(pos.latitude, pos.longitude),
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _gpsAccurate
                            ? NkColors.primaryBlue
                            : NkColors.warningAmber,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
                for (final w in route?.waypoints ?? const [])
                  Marker(
                    point: w.latLng,
                    width: 24,
                    height: 24,
                    child: Icon(
                      w.type == WaypointType.end ? Icons.flag : Icons.circle,
                      color: w.type == WaypointType.end
                          ? NkColors.dangerRed
                          : NkColors.primaryBlue,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 8,
          top: 8,
          child: FilledButton.icon(
            onPressed: () {
              setState(() => _followUser = true);
              if (pos != null) {
                _mapCtrl.move(
                  LatLng(pos.latitude, pos.longitude),
                  _mapCtrl.camera.zoom,
                );
              }
            },
            icon: const Icon(Icons.my_location),
            label: Text(_followUser ? 'Følger deg' : 'Følg meg'),
          ),
        ),
        if (_tileFailed)
          Positioned(
            left: 8,
            right: 8,
            bottom: 100,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Kartfliser kunne ikke lastes. Sjekk nett eller nedlastet område.',
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _mapUrl = _mapUrl == TileCache.urlTemplate
                            ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                            : TileCache.urlTemplate;
                        _tileFailed = false;
                      }),
                      child: const Text('Bytt kartgrunnlag og prøv igjen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // North-up ⇄ heading-up toggle — one-tap, thumb zone.
        Positioned(
          right: 8,
          bottom: 64,
          child: Material(
            color: _headingUp ? NkColors.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _toggleHeadingUp,
              child: Tooltip(
                message: _headingUp
                    ? 'Kurs opp – trykk for nord opp'
                    : 'Nord opp – trykk for kurs opp',
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    _headingUp ? Icons.navigation : Icons.explore_outlined,
                    size: 20,
                    color: _headingUp ? Colors.white : NkColors.primaryBlue,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Expand/collapse toggle — fullscreen map helps on small phones.
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _mapExpanded = !_mapExpanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  _mapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 20,
                  color: NkColors.primaryBlue,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TopBtn(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final Trip trip;
  final Position? position;
  const _ProgressCard({required this.trip, required this.position});

  @override
  Widget build(BuildContext context) {
    final route = trip.route;
    final textStyle = const TextStyle(color: Colors.white);
    double? remaining;
    double? progress;
    LatLng? nextPoint;

    if (route?.hasRoute == true && position != null) {
      final pts = route!.points;
      final pos = LatLng(position!.latitude, position!.longitude);
      final idx = nearestPointIndex(pts, pos);
      final cum = cumulativeDistances(pts);
      final done = cum[idx];
      final total = cum.last;
      remaining = total - done;
      progress = total > 0 ? done / total : 0;
      // First waypoint still ahead along the route.
      var bestAhead = double.infinity;
      for (final w in route.waypoints) {
        final wIdx = nearestPointIndex(pts, w.latLng);
        if (cum[wIdx] > done + 30 && cum[wIdx] < bestAhead) {
          bestAhead = cum[wIdx];
          nextPoint = w.latLng;
        }
      }
      nextPoint ??= route.end;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gjenstår',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      remaining != null ? fmtKm(remaining) : '–',
                      style: textStyle.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (progress != null)
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(
                          NkColors.forestGreen,
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  position == null
                      ? 'Venter på GPS-posisjon…'
                      : 'Neste punkt: ${_nextPointLabel(nextPoint, position!)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          if (trip.trackLog.length >= 2) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timeline, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  'Spor logget: ${fmtKm(_trackDistance())} · ${trip.trackLog.length} punkter',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  double _trackDistance() {
    var m = 0.0;
    for (var i = 1; i < trip.trackLog.length; i++) {
      m += metersBetween(
        LatLng(trip.trackLog[i - 1].lat, trip.trackLog[i - 1].lon),
        LatLng(trip.trackLog[i].lat, trip.trackLog[i].lon),
      );
    }
    return m;
  }

  String _nextPointLabel(LatLng? point, Position pos) {
    if (point == null) return 'ukjent';
    final d = metersBetween(point, LatLng(pos.latitude, pos.longitude));
    return '${fmtKm(d)} unna';
  }
}

class _StageCard extends StatelessWidget {
  final Trip trip;
  final Position? position;
  const _StageCard({required this.trip, required this.position});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    Stage? current;
    for (final s in trip.stages) {
      final d = s.date;
      if (d != null &&
          now.year == d.year &&
          now.month == d.month &&
          now.day == d.day) {
        current = s;
        break;
      }
    }
    current ??= trip.stages.isNotEmpty ? trip.stages.first : null;
    if (current == null) {
      return const SizedBox.shrink();
    }

    double? stageProgress;
    double? stageRemaining;
    if (position != null && current.points.length >= 2) {
      final pos = LatLng(position!.latitude, position!.longitude);
      final idx = nearestPointIndex(current.points, pos);
      final cum = cumulativeDistances(current.points);
      stageProgress = cum.last > 0 ? cum[idx] / cum.last : 0;
      stageRemaining = cum.last - cum[idx];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Etappe ${current.number}: ${current.startName} → ${current.endName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _stat('Etappe', fmtKm(current.distanceMeters)),
              _stat(
                'Gjenstår',
                stageRemaining != null ? fmtKm(stageRemaining) : '–',
              ),
              _stat('Stigning', '+${current.ascent.round()} m'),
              _stat('Tid est.', fmtDuration(current.estimatedMinutes)),
              _stat(
                'Ankomst ca.',
                position != null &&
                        stageRemaining != null &&
                        position!.speed > 0.5
                    ? fmtTime(
                        DateTime.now().add(
                          Duration(
                            minutes:
                                (stageRemaining /
                                        1000 /
                                        (position!.speed * 3.6) *
                                        60)
                                    .round(),
                          ),
                        ),
                      )
                    : '–',
              ),
            ],
          ),
          if (position != null &&
              stageRemaining != null &&
              position!.speed > 0.5) ...[
            Builder(
              builder: (_) {
                final eta = DateTime.now().add(
                  Duration(
                    minutes: (stageRemaining! /
                            1000 /
                            (position!.speed * 3.6) *
                            60)
                        .round(),
                  ),
                );
                final sunset = sunsetAt(
                  DateTime.now(),
                  position!.latitude,
                  position!.longitude,
                );
                if (sunset == null || !eta.isAfter(sunset)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Beregnet fremme ${fmtTime(eta)} – etter solnedgang '
                    '${fmtTime(sunset)}. Vurder å snu eller velge en '
                    'kortere etappe.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber,
                    ),
                  ),
                );
              },
            ),
          ],
          if (stageProgress != null) ...[
            const SizedBox(height: 10),
            NkProgress(stageProgress, color: Colors.white, height: 5),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Degrees → cardinal label, e.g. "135° SO".
String _compass(double heading) {
  const dirs = ['N', 'NØ', 'Ø', 'SØ', 'S', 'SV', 'V', 'NV'];
  return '${heading.round()}° ${dirs[((heading / 45).round()) % 8]}';
}

class _AltCard extends StatelessWidget {
  final Trip trip;
  final Position? position;
  const _AltCard({required this.trip, required this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.terrain, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Høyde (GPS)',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  position?.altitude != null
                      ? '${position!.altitude.round()} moh'
                      : '–',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'GPS-høyde kan være unøyaktig i fjellterreng.',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Posisjon · kurs',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                position != null
                    ? '${position!.latitude.toStringAsFixed(4)}\n${position!.longitude.toStringAsFixed(4)}'
                    : '–',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                position != null && position!.heading >= 0
                    ? _compass(position!.heading)
                    : '',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool alert;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: alert
              ? NkColors.dangerRed
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google-Maps-style view cone painted behind the position dot:
/// a 40° sector pointing along the user's heading, strongest at the
/// apex and fading out — so it reads as a beam, not a pie slice.
/// [alpha] < 1 signals an uncalibrated compass.
class _HeadingCone extends CustomPainter {
  final Color color;
  final double alpha;
  const _HeadingCone({required this.color, this.alpha = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    const half = 20 * math.pi / 180; // 40° beam
    final path = ui.Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 - half,
        2 * half,
        false,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.5 * alpha),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.15, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_HeadingCone old) =>
      old.color != color || old.alpha != alpha;
}
