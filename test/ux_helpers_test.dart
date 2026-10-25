import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/core/format.dart';
import 'package:norgeskompasset/models/route_models.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:norgeskompasset/services/geocoding_service.dart';

Waypoint _wp(String name, WaypointType type) =>
    Waypoint(id: name, name: name, lat: 59.85, lon: 8.65, type: type);

void main() {
  test('fmtCount picks singular or plural', () {
    expect(fmtCount(1, 'dag', 'dager'), '1 dag');
    expect(fmtCount(3, 'dag', 'dager'), '3 dager');
    expect(fmtCount(0, 'etappe', 'etapper'), '0 etapper');
  });

  group('suggestTripName', () {
    test('uses start and goal names', () {
      expect(
        suggestTripName([
          _wp('Stavsro', WaypointType.start),
          _wp('Gaustatoppen', WaypointType.end),
        ]),
        'Stavsro – Gaustatoppen',
      );
    });

    test('falls back to the one real name', () {
      expect(
        suggestTripName([
          _wp('Gaustatoppen', WaypointType.start),
          _wp('Mål (B)', WaypointType.end),
        ]),
        'Gaustatoppen',
      );
    });

    test('same start and goal is a round trip', () {
      expect(
        suggestTripName([
          _wp('Stavsro', WaypointType.start),
          _wp('Stavsro', WaypointType.end),
        ]),
        'Rundtur fra Stavsro',
      );
    });

    test('generic labels give no name', () {
      expect(
        suggestTripName([
          _wp('Start (A)', WaypointType.start),
          _wp('Mål (B)', WaypointType.end),
        ]),
        '',
      );
    });
  });

  group('GeocodingService.placeNameFrom', () {
    test('prefers the object name', () {
      expect(
        GeocodingService.placeNameFrom({'name': 'Gaustatoppen'}),
        'Gaustatoppen',
      );
    });

    test('falls back to address parts', () {
      expect(
        GeocodingService.placeNameFrom({
          'name': '',
          'address': {'hamlet': 'Stavsro', 'municipality': 'Tinn'},
        }),
        'Stavsro',
      );
    });

    test('returns null without usable names', () {
      expect(GeocodingService.placeNameFrom({'address': {}}), isNull);
    });
  });

  group('bestHikingDay', () {
    WeatherHour hour(DateTime t, {double rain = 0, double wind = 2}) =>
        WeatherHour(
          time: t,
          temperature: 10,
          precipitationMm: rain,
          windSpeed: wind,
        );

    test('picks the driest day and returns null for one day', () {
      final day1 = DateTime(2026, 6, 1, 10);
      final day2 = DateTime(2026, 6, 2, 10);
      final hours = [
        for (var i = 0; i < 8; i++)
          hour(day1.add(Duration(hours: i)), rain: 2),
        for (var i = 0; i < 8; i++) hour(day2.add(Duration(hours: i))),
      ];
      final best = bestHikingDay(hours);
      expect(best?.day, DateTime(2026, 6, 2));
      expect(bestHikingDay(hours.sublist(0, 8)), isNull);
    });
  });
}
