import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../models/route_models.dart';

enum TrackingPhase { idle, starting, active, paused, stopping, error }

abstract class TrackingLocationSource {
  Future<void> prepare();
  Future<Position?> lastKnown();
  Stream<Position> positions();
}

class GeolocatorTrackingSource implements TrackingLocationSource {
  @override
  Future<void> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Posisjonstjenester er avslått.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Gi posisjonstilgang i telefonens innstillinger.');
    }
  }

  @override
  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();

  @override
  Stream<Position> positions() {
    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Foreground service keeps the track recording alive with the
      // screen off — critical for multi-hour hikes.
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'NorgesKompasset – turmodus',
          notificationText: 'Spor og avviksvarsling er aktiv i bakgrunnen.',
          enableWakeLock: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 5,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}

class TrackingController extends ChangeNotifier {
  final TrackingLocationSource source;
  final Future<void> Function(String tripId, Position position) onPosition;
  final Future<void> Function(String tripId) onFlush;
  TrackingController({
    required this.source,
    required this.onPosition,
    required this.onFlush,
    this.routeProvider,
    this.onOffRouteAlert,
  });

  /// Route geometry to measure deviation against (null = alerts off,
  /// e.g. for estimated or imported routes that are not verified
  /// navigation corridors).
  final List<RoutePoint>? Function()? routeProvider;

  /// Fired when the hiker has been off-route for two consecutive
  /// fixes, throttled to once per [_alertCooldown].
  final void Function(double deviationMeters)? onOffRouteAlert;

  static const offRouteThresholdMeters = 80.0;
  static const _alertCooldown = Duration(minutes: 5);

  TrackingPhase phase = TrackingPhase.idle;
  String? tripId;
  Position? position;
  String? error;
  double? deviationMeters;
  bool offRoute = false;
  int _offRouteCount = 0;
  DateTime? _lastOffRouteAlert;
  StreamSubscription<Position>? _subscription;
  Future<void> _writes = Future.value();
  int _generation = 0;
  bool _disposed = false;
  bool get isActive => phase == TrackingPhase.active;
  bool get isBusy =>
      phase == TrackingPhase.starting || phase == TrackingPhase.stopping;
  bool _valid(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(String id) async {
    if (_disposed || isBusy || isActive) return;
    if (tripId != null && tripId != id) await stop();
    if (_disposed) return;
    final generation = ++_generation;
    tripId = id;
    phase = TrackingPhase.starting;
    error = null;
    _offRouteCount = 0;
    offRoute = false;
    deviationMeters = null;
    _lastOffRouteAlert = null;
    _notify();
    try {
      await source.prepare();
      if (!_valid(generation)) return;
      try {
        position = await source.lastKnown();
      } catch (_) {}
      if (!_valid(generation)) return;
      phase = TrackingPhase.active;
      _subscription = source.positions().listen(
        (next) {
          if (!_valid(generation) || !isActive) return;
          position = next;
          _updateDeviation(next);
          _writes = _writes
              .then((_) async {
                if (!_disposed) await onPosition(id, next);
              })
              .then((_) {
                if (_valid(generation)) _notify();
              })
              .catchError((Object e) {
                if (_valid(generation)) {
                  _fail('Kunne ikke lagre sporet. Sporing er stoppet.');
                }
              });
          _notify();
        },
        onError: (Object e) {
          if (_valid(generation)) {
            _fail('GPS-strømmen er avbrutt. Kontroller GPS og start på nytt.');
          }
        },
        onDone: () {
          if (_valid(generation)) {
            _fail('GPS-strømmen ble avsluttet. Start sporing på nytt.');
          }
        },
      );
      _notify();
    } catch (e) {
      if (_valid(generation)) _fail('Kunne ikke starte GPS-sporing: $e');
    }
  }

  /// Off-route detection lives here — not in the UI — so the alert
  /// also fires while the screen is off (the Android foreground
  /// service keeps the stream alive). Two consecutive fixes beyond
  /// the threshold are required; a single bad fix is noise.
  void _updateDeviation(Position pos) {
    final route = routeProvider?.call();
    if (route == null || route.isEmpty) {
      _offRouteCount = 0;
      offRoute = false;
      deviationMeters = null;
      return;
    }
    final dev = distanceToRouteMeters(
      route,
      LatLng(pos.latitude, pos.longitude),
    );
    deviationMeters = dev;
    if (dev > offRouteThresholdMeters) {
      _offRouteCount++;
    } else {
      _offRouteCount = 0;
    }
    offRoute = _offRouteCount >= 2;
    if (offRoute) {
      final now = DateTime.now();
      final last = _lastOffRouteAlert;
      if (last == null || now.difference(last) >= _alertCooldown) {
        _lastOffRouteAlert = now;
        onOffRouteAlert?.call(dev);
      }
    }
  }

  void _fail(String message) {
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    error = message;
    phase = TrackingPhase.error;
    _notify();
  }

  Future<void> flush() async {
    await _writes;
    final id = tripId;
    if (id != null) await onFlush(id);
  }

  Future<void> _finish(TrackingPhase target) async {
    if (_disposed) return;
    final generation = ++_generation;
    phase = TrackingPhase.stopping;
    final subscription = _subscription;
    _subscription = null;
    _notify();
    try {
      await subscription?.cancel();
      await flush();
      if (!_valid(generation)) return;
      phase = target;
      if (target == TrackingPhase.idle) {
        tripId = null;
        position = null;
      }
    } catch (_) {
      if (!_valid(generation)) return;
      phase = TrackingPhase.error;
      error =
          'Kunne ikke lagre siste sporpunkter. Prøv igjen før du bytter tur.';
    }
    _notify();
  }

  Future<void> pause() => _finish(TrackingPhase.paused);
  Future<void> stop() => _finish(TrackingPhase.idle);

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
