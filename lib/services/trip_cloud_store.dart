import 'package:cloud_firestore/cloud_firestore.dart';

class CloudTripRecord {
  final String? data;
  final DateTime updatedAt;
  final bool deleted;

  const CloudTripRecord({
    this.data,
    required this.updatedAt,
    this.deleted = false,
  });

  Map<String, dynamic> toJson() => {
    'data': data,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };

  factory CloudTripRecord.fromJson(Map<String, dynamic> json) =>
      CloudTripRecord(
        data: json['data'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        deleted: json['deleted'] as bool? ?? false,
      );
}

enum TripSyncPhase { localOnly, pending, syncing, synced, error, conflict }

class TripSyncStatus {
  final TripSyncPhase phase;
  final int pendingCount;
  final String? message;
  const TripSyncStatus({
    this.phase = TripSyncPhase.localOnly,
    this.pendingCount = 0,
    this.message,
  });

  String get label => switch (phase) {
    TripSyncPhase.localOnly => 'Lagret lokalt',
    TripSyncPhase.pending =>
      pendingCount == 0
          ? 'Klar til synkronisering'
          : '$pendingCount endringer venter på synkronisering',
    TripSyncPhase.syncing => 'Synkroniserer …',
    TripSyncPhase.synced => 'Synkronisert',
    TripSyncPhase.error =>
      message ?? 'Synkronisering feilet – lokale data er bevart',
    TripSyncPhase.conflict =>
      'Konflikt med skyversjon – lokale endringer er bevart',
  };
}

abstract class TripCloudStore {
  Future<Map<String, CloudTripRecord>> readTrips(String uid);
  Future<bool> apply(String uid, String id, CloudTripRecord record);
}

class FirestoreTripCloudStore implements TripCloudStore {
  final FirebaseFirestore db;
  FirestoreTripCloudStore(this.db);

  @override
  Future<Map<String, CloudTripRecord>> readTrips(String uid) async {
    final snapshot = await db
        .collection('users')
        .doc(uid)
        .collection('trips')
        .get(const GetOptions(source: Source.server));
    return {
      for (final doc in snapshot.docs)
        doc.id: CloudTripRecord.fromJson(doc.data()),
    };
  }

  @override
  Future<bool> apply(String uid, String id, CloudTripRecord record) =>
      db.runTransaction((transaction) async {
        final ref = db.collection('users').doc(uid).collection('trips').doc(id);
        final snapshot = await transaction.get(ref);
        if (snapshot.exists) {
          final current = CloudTripRecord.fromJson(snapshot.data()!);
          if (current.updatedAt.isAfter(record.updatedAt)) return false;
        }
        transaction.set(ref, record.toJson());
        return true;
      });
}
