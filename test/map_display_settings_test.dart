import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/map_display_settings.dart';

void main() {
  test('automatic mode uses topo locally and OSM for world overview', () {
    final settings = MapDisplaySettings();
    expect(settings.automatic, isTrue);
    expect(settings.baseForZoom(5.5), MapDisplaySettings.osm);
    expect(settings.baseForZoom(6), MapDisplaySettings.kartverket);
    expect(settings.baseForZoom(13), MapDisplaySettings.kartverket);
  });

  test('ski activity enables overlay but foot, bike and paddle do not', () {
    final settings = MapDisplaySettings();
    expect(settings.skiFor(TripActivity.ski), isTrue);
    for (final activity in [
      null,
      TripActivity.foot,
      TripActivity.bike,
      TripActivity.paddle,
    ]) {
      expect(settings.skiFor(activity), isFalse);
    }
    final pulkOnFoot = Trip(
      id: 'foot-pulk',
      activity: TripActivity.foot,
      carry: CarryMode.pulk,
    );
    expect(settings.skiFor(pulkOnFoot.activity), isFalse);
  });

  test('manual choices survive activity and zoom changes until reset', () {
    final settings = MapDisplaySettings()
      ..baseOverride = MapDisplaySettings.openTopo
      ..skiOverride = false;
    expect(settings.automatic, isFalse);
    expect(settings.baseForZoom(3), MapDisplaySettings.openTopo);
    expect(settings.baseForZoom(14), MapDisplaySettings.openTopo);
    expect(settings.skiFor(TripActivity.ski), isFalse);
    settings.reset();
    expect(settings.automatic, isTrue);
    expect(settings.skiFor(TripActivity.ski), isTrue);
    expect(settings.baseForZoom(14), MapDisplaySettings.kartverket);
    expect(settings.skiFor(TripActivity.foot), isFalse);
  });
}
