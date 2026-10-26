import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/calendar_event.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/events_service.dart';
import 'package:norgeskompasset/services/trip_repository.dart';
import 'package:norgeskompasset/state/app_state.dart';

class _Repo extends TripRepository {
  final saved = <Trip>[];
  @override
  Future<void> saveTrip(Trip trip, {bool syncCloud = true}) async {
    saved.add(trip);
  }
}

const _body = '''
{"events":[
 {"id":"b","title":"Kompass-treff på Brygg 25. november","description":"Sosialt",
  "start":"2026-11-25T18:00:00.000Z","end":"2026-11-25T21:00:00.000Z",
  "locationName":"Brygg","address":"Oslo","url":"https://www.norgeskompasset.no/event-details/treff","price":0,"currency":"NOK"},
 {"id":"a","title":"Fjelleventyr i Jotunheimen","description":"Hytte til hytte",
  "start":"2027-08-26T06:30:00.000Z","end":"2027-08-29T15:30:00.000Z",
  "formatted":"26.–29. august 2027","locationName":"Bygdin Høifieldshotel",
  "address":"Beitostølen","lat":61.3,"lon":8.8,
  "image":"https://static.wixstatic.com/media/x.jpg",
  "url":"https://www.norgeskompasset.no/event-details/fjelleventyr-i-jotunheimen",
  "price":1998.75,"currency":"NOK","soldOut":false,"registrationOpen":true},
 {"id":"bad","title":"Uten dato"}
]}
''';

void main() {
  test('calendar parses, sorts and classifies events', () {
    final events = EventsService.parse(_body);
    expect(events.length, 2);
    expect(events.first.id, 'b'); // sorted by start
    expect(events.first.kind, EventKind.treff);
    expect(events.first.priceLabel, 'Gratis');
    final jotun = events.last;
    expect(jotun.kind, EventKind.tur);
    expect(jotun.multiDay, isTrue);
    expect(jotun.priceLabel, 'fra 1999 kr');
    expect(jotun.place, 'Bygdin Høifieldshotel, Beitostølen');
    // Round-trips through the local cache format.
    final again = CalendarEvent.fromJson(jotun.toJson())!;
    expect(again.start, jotun.start);
    expect(again.url, jotun.url);
  });

  test('starting a trip from an event fills dates, name and notes', () async {
    final repo = _Repo();
    final state = AppState(repo);
    addTearDown(state.dispose);
    final event = EventsService.parse(_body).last;
    final trip = await state.startFromEvent(event);
    expect(trip.name, 'Fjelleventyr i Jotunheimen');
    expect(trip.startDate!.month, 8);
    expect(trip.hikingDays, 4);
    expect(trip.season, TripSeason.summer);
    expect(trip.accommodation, AccommodationType.cabin);
    expect(trip.notes, contains('Bygdin'));
    expect(trip.notes, contains(event.url));
    expect(trip.packingList, isNotEmpty);
    expect(repo.saved, hasLength(1));
    expect(state.currentTripId, trip.id);
  });
}
