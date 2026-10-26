import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/app_info.dart';
import '../models/calendar_event.dart';

/// Reads the tour calendar from Firestore (`config/events`). The document
/// is written every hour by the `refreshEvents` Cloud Function, which
/// fetches Wix Events with the API key kept server-side.
class EventsService {
  final FirebaseFirestore? _db;
  EventsService([FirebaseFirestore? db]) : _db = db;

  Future<List<CalendarEvent>> fetch({bool refresh = false}) async {
    if (_db == null && Firebase.apps.isEmpty) {
      throw StateError('Firebase er ikke satt opp');
    }
    final db = _db ?? FirebaseFirestore.instance;
    final snap = await db
        .doc(kEventsDoc)
        .get(
          GetOptions(source: refresh ? Source.server : Source.serverAndCache),
        )
        .timeout(const Duration(seconds: 20));
    final data = snap.data();
    if (data == null) return const [];
    return parseList(data['events']);
  }

  static List<CalendarEvent> parse(String body) {
    final json = jsonDecode(body);
    return parseList(json is Map ? json['events'] : json);
  }

  static List<CalendarEvent> parseList(Object? raw) {
    if (raw is! List) return const [];
    final events = <CalendarEvent>[
      for (final e in raw)
        if (e is Map) ?CalendarEvent.fromJson(_plain(e)),
    ];
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  /// Firestore returns Timestamps for date fields written server-side;
  /// the model expects ISO strings.
  static Map<String, dynamic> _plain(Map e) => {
    for (final entry in e.entries)
      entry.key.toString(): entry.value is Timestamp
          ? (entry.value as Timestamp).toDate().toUtc().toIso8601String()
          : entry.value,
  };
}
