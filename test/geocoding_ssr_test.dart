import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:norgeskompasset/services/geocoding_service.dart';

void main() {
  test('search keeps the official mountain ahead of a relic name', () {
    final places = parseSsrSearch({
      'navn': [
        {
          'fylker': [
            {'fylkesnavn': 'Telemark'},
          ],
          'kommuner': [
            {'kommunenavn': 'Porsgrunn'},
          ],
          'navneobjekttype': 'Topp',
          'navnestatus': 'historisk',
          'representasjonspunkt': {'nord': 59.18, 'øst': 9.86},
          'skrivemåte': 'Galdhøpiggen',
          'skrivemåtestatus': 'historisk og prioritert',
          'stedstatus': 'relikt',
        },
        {
          'fylker': [
            {'fylkesnavn': 'Innlandet'},
          ],
          'kommuner': [
            {'kommunenavn': 'Lom'},
          ],
          'navneobjekttype': 'Fjell',
          'navnestatus': 'hovednavn',
          'representasjonspunkt': {'nord': 61.63644, 'øst': 8.31248},
          'skrivemåte': 'Galdhøpiggen',
          'skrivemåtestatus': 'godkjent og prioritert',
          'stedstatus': 'aktiv',
        },
      ],
    }, query: 'Galdhøpiggen');

    expect(places, hasLength(2));
    expect(places.first.name, 'Galdhøpiggen');
    expect(places.first.point, const LatLng(61.63644, 8.31248));
    expect(places.first.source, 'Kartverket');
    expect(places.first.displayName, 'Fjell · Lom, Innlandet · Kartverket');
    expect(places.last.displayName, contains('Porsgrunn'));
  });

  test('point lookup uses the closest active name', () {
    final name = closestSsrName({
      'navn': [
        {
          'meterFraPunkt': 285,
          'navneobjekttype': 'Skar',
          'representasjonspunkt': {'nord': 61.638, 'øst': 8.308},
          'stedsnavn': [
            {
              'navnestatus': 'hovednavn',
              'skrivemåte': 'Porten',
              'skrivemåtestatus': 'godkjent og prioritert',
            },
          ],
          'stedstatus': 'aktiv',
        },
        {
          'meterFraPunkt': 0,
          'navneobjekttype': 'Fjell',
          'representasjonspunkt': {'nord': 61.63644, 'øst': 8.31248},
          'stedsnavn': [
            {
              'navnestatus': 'hovednavn',
              'skrivemåte': 'Galdhøpiggen',
              'skrivemåtestatus': 'godkjent og prioritert',
            },
          ],
          'stedstatus': 'aktiv',
        },
      ],
    });
    expect(name, 'Galdhøpiggen');
  });

  test('point lookup ignores names farther than one kilometre', () {
    expect(
      closestSsrName({
        'navn': [
          {
            'meterFraPunkt': 1400,
            'navneobjekttype': 'Fjell',
            'representasjonspunkt': {'nord': 60, 'øst': 8},
            'stedsnavn': [
              {'skrivemåte': 'Langt unna', 'skrivemåtestatus': 'vedtatt'},
            ],
            'stedstatus': 'aktiv',
          },
        ],
      }),
      isNull,
    );
  });
}
