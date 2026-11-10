import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/services/hut_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled register includes Finsehytta near Finse', () async {
    final huts = await HutService().fetchInBounds(60.55, 7.45, 60.65, 7.55);
    expect(huts.map((h) => h.name), contains('Finsehytta'));
    expect(
      huts.firstWhere((h) => h.name == 'Finsehytta').kind,
      HutKind.staffed,
    );
  });

  test('compact row keeps operator, beds and opening hours', () {
    final hut = hutFromCompact([
      'Finsehytta',
      60.6,
      7.5,
      1,
      1222,
      'DNT',
      '140',
      'Jun-Sep',
    ]);
    expect(hut, isNotNull);
    expect(hut!.operator, 'DNT');
    expect(hut.capacity, '140');
    expect(hut.openingHours, 'Jun-Sep');
    final bare = hutFromCompact(['Koia', 60, 7, 0, null]);
    expect(bare!.openingHours, isEmpty);
    expect(bare.operator, isEmpty);
  });

  test('parses staffed nodes and unstaffed building ways', () {
    final huts = parseHuts({
      'elements': [
        {
          'type': 'node',
          'id': 1,
          'lat': 60.5,
          'lon': 7.5,
          'tags': {
            'tourism': 'alpine_hut',
            'name': 'Finsehytta',
            'ele': '1222',
            'operator': 'DNT',
            'capacity': '140',
          },
        },
        {
          'type': 'way',
          'id': 2,
          'center': {'lat': 61.1, 'lon': 8.2},
          'tags': {'tourism': 'wilderness_hut', 'name': 'Geiterygghytta'},
        },
        {
          'type': 'node',
          'id': 3,
          'lat': 59,
          'lon': 10,
          'tags': {'tourism': 'hotel', 'name': 'Ikke en turhytte'},
        },
      ],
    });
    expect(huts, hasLength(2));
    expect(huts.first.name, 'Finsehytta');
    expect(huts.first.kind, HutKind.staffed);
    expect(huts.first.elevation, 1222);
    expect(huts.first.operator, 'DNT');
    expect(huts.last.kind, HutKind.unstaffed);
    expect(huts.last.point.latitude, 61.1);
  });
}
