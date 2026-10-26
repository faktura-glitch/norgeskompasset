import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_info.dart';
import '../core/http_identity.dart';
import '../models/calendar_event.dart';

/// Fetches the tour calendar from the `events` Cloud Function, which
/// proxies Wix Events with the API key kept server-side.
class EventsService {
  final http.Client _client;
  EventsService([http.Client? client]) : _client = client ?? http.Client();

  Future<List<CalendarEvent>> fetch({bool refresh = false}) async {
    final uri = Uri.parse(
      refresh ? '$kEventsEndpoint?refresh=1' : kEventsEndpoint,
    );
    final res = await _client
        .get(uri, headers: const {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('Turkalender svarte ${res.statusCode}', uri);
    }
    return parse(utf8.decode(res.bodyBytes));
  }

  static List<CalendarEvent> parse(String body) {
    final json = jsonDecode(body);
    final raw = json is Map ? json['events'] : json;
    if (raw is! List) return const [];
    final events = <CalendarEvent>[
      for (final e in raw)
        if (e is Map) ?CalendarEvent.fromJson(Map<String, dynamic>.from(e)),
    ];
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }
}
