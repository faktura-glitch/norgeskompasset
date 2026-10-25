import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:norgeskompasset/services/tile_cache.dart';
import 'package:norgeskompasset/state/app_state.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/track.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/models/profile.dart';
import 'package:norgeskompasset/services/trip_cloud_store.dart';
import 'package:norgeskompasset/services/trip_repository.dart';

class MemoryCloud implements TripCloudStore {
  final users = <String, Map<String, CloudTripRecord>>{};
  bool offline = false;
  Completer<void>? hold;

  @override
  Future<Map<String, CloudTripRecord>> readTrips(String uid) async {
    if (offline) throw StateError('offline');
    return Map.of(users[uid] ?? {});
  }

  @override
  Future<bool> apply(String uid, String id, CloudTripRecord record) async {
    await hold?.future;
    if (offline) throw StateError('offline');
    final docs = users.putIfAbsent(uid, () => {});
    if (docs[id]?.updatedAt.isAfter(record.updatedAt) == true) return false;
    docs[id] = record;
    return true;
  }
}

void main() {
  late Directory directory;
  late MemoryCloud cloud;
  late TripRepository repo;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('norgeskompasset-sync-');
    cloud = MemoryCloud();
    repo = TripRepository(storagePath: directory.path, cloudStore: cloud);
    await repo.init();
  });

  tearDown(() async {
    cloud.hold?.complete();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('guest and accounts have separate local trips', () async {
    await repo.saveTrip(Trip(id: 'guest'), syncCloud: false);
    await Future.sync(() => repo.setUser('Alice'));
    expect(repo.loadTrips(), isEmpty);
    await repo.saveTrip(Trip(id: 'alice'), syncCloud: false);
    await Future.sync(() => repo.setUser('Bob'));
    expect(repo.loadTrips(), isEmpty);
    await Future.sync(() => repo.setUser('Alice'));
    expect(repo.loadTrips().map((t) => t.id), ['alice']);
    await Future.sync(() => repo.setUser(null));
    expect(repo.loadTrips().map((t) => t.id), ['guest']);
  });

  test('a newer local version of an existing cloud trip is uploaded', () async {
    await Future.sync(() => repo.setUser('alice'));
    final trip = Trip(id: 'same', name: 'Lokalt');
    cloud.users['alice'] = {
      'same': CloudTripRecord(
        data: (Trip(
          id: 'same',
          name: 'Gammelt',
        )..updatedAt = DateTime(2020)).encode(),
        updatedAt: DateTime(2020),
      ),
    };
    await repo.saveTrip(trip, syncCloud: false);
    await repo.syncFromCloud();
    expect(Trip.decode(cloud.users['alice']!['same']!.data!).name, 'Lokalt');
  });

  test('pending changes survive reopening the repository', () async {
    await repo.setUser('alice');
    await repo.saveTrip(Trip(id: 'pending'), syncCloud: false);
    final reopened = TripRepository(
      storagePath: directory.path,
      cloudStore: cloud,
    );
    await reopened.init();
    await reopened.setUser('alice');
    expect(reopened.pendingCount, 1);
    await reopened.syncFromCloud();
    expect(cloud.users['alice']!.containsKey('pending'), isTrue);
    expect(reopened.pendingCount, 0);
  });

  test('pending compact upload never replaces the full local trip', () async {
    await repo.setUser('alice');
    final trip = Trip(id: 'offline', name: 'Spor beholdes')
      ..trackLog = [TrackPoint(60, 8, 100, DateTime.now())]
      ..weather['route'] = WeatherSnapshot(
        lat: 60,
        lon: 8,
        retrievedAt: DateTime.now(),
        hours: [WeatherHour(time: DateTime.now(), temperature: -3)],
      );
    await repo.saveTrip(trip, syncCloud: false);

    // Switching accounts replays the upload queue, as does a restart.
    await repo.setUser(null);
    await repo.setUser('alice');
    final local = repo.loadTrips().single;
    expect(local.trackLog, hasLength(1));
    expect(local.weather['route']!.hours, hasLength(1));
    expect(repo.pendingCount, 1);
    await repo.syncFromCloud();
    expect(repo.loadTrips().single.trackLog, hasLength(1));
  });

  test('newer v2 plan retains the device-local GPS track', () async {
    await repo.setUser('alice');
    final trip = Trip(id: 'tracked')
      ..trackLog = [TrackPoint(60, 8, 100, DateTime.now())];
    await repo.saveTrip(trip, syncCloud: false);
    await repo.syncFromCloud();
    final remote = Trip(id: 'tracked', name: 'Ny plan')
      ..updatedAt = DateTime.now().add(const Duration(hours: 1));
    cloud.users['alice']!['tracked'] = CloudTripRecord(
      data: jsonEncode(remote.toSyncJson()),
      updatedAt: remote.updatedAt,
    );

    await repo.syncFromCloud();
    final local = repo.loadTrips().single;
    expect(local.name, 'Ny plan');
    expect(local.trackLog, hasLength(1));
  });

  test(
    'offline deletion stays deleted and is retried as a tombstone',
    () async {
      await repo.setUser('alice');
      await repo.saveTrip(Trip(id: 'delete'), syncCloud: false);
      await repo.syncFromCloud();
      cloud.offline = true;
      await repo.deleteTrip('delete');
      await expectLater(repo.syncFromCloud(), throwsA(anything));
      expect(repo.loadTrips(), isEmpty);
      cloud.offline = false;
      await repo.syncFromCloud();
      expect(repo.loadTrips(), isEmpty);
      expect(cloud.users['alice']!['delete']!.deleted, isTrue);
    },
  );

  test(
    'newer remote data does not silently destroy pending local edits',
    () async {
      await repo.setUser('alice');
      await repo.saveTrip(
        Trip(id: 'conflict', name: 'Lokalt'),
        syncCloud: false,
      );
      final remote = Trip(id: 'conflict', name: 'Eksternt')
        ..updatedAt = DateTime(2090);
      cloud.users['alice'] = {
        'conflict': CloudTripRecord(
          data: remote.encode(),
          updatedAt: remote.updatedAt,
        ),
      };
      await repo.syncFromCloud();
      expect(repo.loadTrips().single.name, 'Lokalt');
      expect(repo.cloudConflictIds, contains('conflict'));
      expect(repo.pendingCount, 1);
      expect(
        Trip.decode(cloud.users['alice']!['conflict']!.data!).name,
        'Eksternt',
      );
    },
  );

  test(
    'a trip object loaded for another account cannot be saved here',
    () async {
      await repo.setUser('alice');
      await repo.saveTrip(Trip(id: 'private'), syncCloud: false);
      final old = repo.loadTrips().single;
      await repo.setUser('bob');
      await expectLater(repo.saveTrip(old), throwsStateError);
      expect(repo.loadTrips(), isEmpty);
    },
  );

  test('offline coverage invalidates on tile changes and equal-sized route replacement', () async {
    final state = AppState(repo);
    final trip = Trip(id: 'route')
      ..route = HikingRoute(
        points: [RoutePoint(60, 8), RoutePoint(60.01, 8.01)],
        distanceMeters: 1000,
      );
    final first = state.offlineCoverage(trip);
    expect(first.cached, 0);
    TileCache.write(
      TileCache.urlsCovering(trip.route!.latLngs).first,
      Uint8List.fromList([1, 2]),
    );
    expect(state.offlineCoverage(trip).cached, 1);
    trip.route = HikingRoute(
      points: [RoutePoint(62, 10), RoutePoint(62.01, 10.01)],
      distanceMeters: 1000,
    );
    expect(state.offlineCoverage(trip).cached, 0);
    await state.clearMapCache();
    expect(state.offlineCoverage(trip).cached, 0);
  });

  test('profiles are account scoped', () async {
    await repo.setUser('alice');
    await repo.saveProfile(UserProfile(name: 'Alice'));
    await repo.setUser('bob');
    expect(repo.loadProfile().name, isEmpty);
    await repo.setUser('alice');
    expect(repo.loadProfile().name, 'Alice');
  });

  test(
    'offline sync reports failure instead of an empty successful sync',
    () async {
      await Future.sync(() => repo.setUser('alice'));
      cloud.offline = true;
      await expectLater(repo.syncFromCloud(), throwsA(anything));
    },
  );
}
