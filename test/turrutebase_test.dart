import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/services/turrutebase_service.dart';

const _gml = '''<?xml version='1.0' encoding='UTF-8'?>
<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0"
    xmlns:gml="http://www.opengis.net/gml/3.2"
    xmlns:app="http://skjema.geonorge.no/SOSI/produktspesifikasjon/TurOgFriluftsruter/20171210">
  <wfs:member>
    <app:Fotrute gml:id="fotrute.11512">
      <app:senterlinje>
        <gml:LineString srsName="urn:ogc:def:crs:EPSG::4258">
          <gml:posList>59.904201 10.896647 59.903906 10.896720 59.903631 10.897049 59.9 10.9</gml:posList>
        </gml:LineString>
      </app:senterlinje>
      <app:fotruteInfo>
        <app:FotruteInfo>
          <app:rutenavn>Blåmerket sti Østmarka</app:rutenavn>
          <app:rutenummer>F_01</app:rutenummer>
          <app:vedlikeholdsansvarlig>Friluftsetaten</app:vedlikeholdsansvarlig>
          <app:gradering>ENKEL</app:gradering>
        </app:FotruteInfo>
      </app:fotruteInfo>
    </app:Fotrute>
  </wfs:member>
  <wfs:member>
    <app:Skiløype gml:id="skiloypa.7">
      <app:senterlinje>
        <gml:LineString srsName="urn:ogc:def:crs:EPSG::4258">
          <gml:posList>60.0 11.0 60.01 11.0</gml:posList>
        </gml:LineString>
      </app:senterlinje>
      <app:skiløypeInfo>
        <app:SkiløypeInfo>
          <app:rutenavn>Klassisk løype</app:rutenavn>
        </app:SkiløypeInfo>
      </app:skiløypeInfo>
    </app:Skiløype>
  </wfs:member>
  <wfs:member>
    <app:RuteInfoPunkt gml:id="p.1">
      <app:senterlinje>
        <gml:Point><gml:pos>60.0 11.0</gml:pos></gml:Point>
      </app:senterlinje>
    </app:RuteInfoPunkt>
  </wfs:member>
  <wfs:member>
    <app:Fotrute gml:id="fotrute.99">
      <app:senterlinje>
        <gml:LineString><gml:posList>60.0 11.0</gml:posList></gml:LineString>
      </app:senterlinje>
    </app:Fotrute>
  </wfs:member>
</wfs:FeatureCollection>''';

void main() {
  group('Turrutebase parser', () {
    test('parses route features and skips non-routes/degenerate lines', () {
      final trails = TurrutebaseService.parse(_gml);
      expect(trails.length, 2);
      final foot = trails.firstWhere((t) => t.type == TrailType.foot);
      expect(foot.id, 'fotrute.11512');
      expect(foot.name, 'Blåmerket sti Østmarka');
      expect(foot.maintainer, 'Friluftsetaten');
      expect(foot.grading, 'ENKEL');
      expect(foot.points.length, 4);
      // EPSG:4258 is lat,lon — first pair must read lat then lon.
      expect(foot.points.first.lat, closeTo(59.904201, 1e-6));
      expect(foot.points.first.lon, closeTo(10.896647, 1e-6));
      expect(foot.distanceMeters, greaterThan(0));
      final ski = trails.firstWhere((t) => t.type == TrailType.ski);
      expect(ski.name, 'Klassisk løype');
    });
  });

  test('registered routes search name, maintainer, type and number', () {
    final trails = TurrutebaseService.parse(_gml);
    final foot = trails.first;
    expect(foot.matchesQuery('  ØSTMARKA '), isTrue);
    expect(foot.matchesQuery('friluftsetaten'), isTrue);
    expect(foot.matchesQuery('fotrute'), isTrue);
    expect(foot.matchesQuery('f_01'), isTrue);
    expect(foot.matchesQuery(''), isTrue);
    expect(foot.matchesQuery('ukjent'), isFalse);
    expect(trails.where((t) => t.matchesQuery('skiløype')).length, 1);
  });

  group('Seasonal filtering', () {
    test('winter months fetch ski tracks only', () {
      final t = TurrutebaseService.seasonalTypes(DateTime(2026, 1, 15), null);
      expect(t, {TrailType.ski});
      final nov = TurrutebaseService.seasonalTypes(DateTime(2026, 11, 1), null);
      expect(nov, {TrailType.ski});
    });

    test('summer months fetch foot and bike routes', () {
      final t = TurrutebaseService.seasonalTypes(DateTime(2026, 7, 1), null);
      expect(t, {TrailType.foot, TrailType.bike});
    });

    test('an explicit trip season overrides the calendar', () {
      final t = TurrutebaseService.seasonalTypes(
        DateTime(2026, 7, 1),
        TripSeason.winter,
      );
      expect(t, {TrailType.ski});
      final s = TurrutebaseService.seasonalTypes(
        DateTime(2026, 1, 15),
        TripSeason.summer,
      );
      expect(s, {TrailType.foot, TrailType.bike});
    });

    test('seasonForDate maps months to app seasons', () {
      expect(
        TurrutebaseService.seasonForDate(DateTime(2026, 4, 1)),
        TripSeason.spring,
      );
      expect(
        TurrutebaseService.seasonForDate(DateTime(2026, 7, 1)),
        TripSeason.summer,
      );
      expect(
        TurrutebaseService.seasonForDate(DateTime(2026, 10, 1)),
        TripSeason.autumn,
      );
      expect(
        TurrutebaseService.seasonForDate(DateTime(2026, 12, 1)),
        TripSeason.winter,
      );
    });
  });
}
