import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:norgeskompasset/services/tracking_controller.dart';

class FakeLocationSource implements TrackingLocationSource {
  Completer<void>? preparing;
  final events = StreamController<Position>.broadcast(sync: true);
  int subscriptions = 0;
  @override
  Future<void> prepare() async {
    await preparing?.future;
  }

  @override
  Future<Position?> lastKnown() async => null;
  @override
  Stream<Position> positions() {
    subscriptions++;
    return events.stream;
  }
}

Position fix() => Position(
  latitude: 60,
  longitude: 8,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 100,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 1,
  speedAccuracy: 1,
);

void main() {
  late FakeLocationSource source;
  late TrackingController controller;
  late List<String> recorded;
  late List<String> flushed;
  setUp(() {
    source = FakeLocationSource();
    recorded = [];
    flushed = [];
    controller = TrackingController(
      source: source,
      onPosition: (id, position) async {
        recorded.add(id);
      },
      onFlush: (id) async {
        flushed.add(id);
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await source.events.close();
  });

  test('pause invalidates a permission request still in progress', () async {
    source.preparing = Completer<void>();
    final starting = controller.start('trip-a');
    await controller.pause();
    source.preparing!.complete();
    await starting;
    expect(controller.phase, TrackingPhase.paused);
    expect(source.subscriptions, 0);
    expect(recorded, isEmpty);
  });

  test('stopping during startup never attaches a late stream', () async {
    source.preparing = Completer<void>();
    final starting = controller.start('trip-a');
    await controller.stop();
    source.preparing!.complete();
    await starting;
    expect(controller.phase, TrackingPhase.idle);
    expect(source.subscriptions, 0);
  });

  test(
    'positions stay bound to the trip used when recording started',
    () async {
      await controller.start('trip-a');
      source.events.add(fix());
      await controller.pause();
      source.events.add(fix());
      await Future<void>.delayed(Duration.zero);
      expect(recorded, ['trip-a']);
      expect(flushed, ['trip-a']);
      await controller.start('trip-b');
      source.events.add(fix());
      await controller.pause();
      expect(recorded, ['trip-a', 'trip-b']);
    },
  );

  test('dispose during permission lookup never attaches a stream', () async {
    source.preparing = Completer<void>();
    final disposable = TrackingController(
      source: source,
      onPosition: (_, _) async {},
      onFlush: (_) async {},
    );
    final starting = disposable.start('trip-a');
    disposable.dispose();
    source.preparing!.complete();
    await starting;
    expect(source.subscriptions, 0);
  });

  test('repeated starts do not create duplicate subscriptions', () async {
    source.preparing = Completer<void>();
    final first = controller.start('trip-a');
    await controller.start('trip-a');
    source.preparing!.complete();
    await first;
    expect(source.subscriptions, 1);
  });

  test('stream errors leave active state and permit retry', () async {
    await controller.start('trip-a');
    source.events.addError(StateError('GPS lost'));
    expect(controller.phase, TrackingPhase.error);
    expect(controller.error, isNotNull);
    await controller.start('trip-a');
    expect(controller.phase, TrackingPhase.active);
  });
}
