import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/models/profile.dart';

PackingItem _item(
  String id,
  PackingCategory cat, {
  PackingPriority priority = PackingPriority.required,
  bool packed = false,
  bool worn = false,
  double grams = 100,
}) => PackingItem(
  id: id,
  name: id,
  category: cat,
  unitWeightGrams: grams,
  priority: priority,
  packed: packed,
  worn: worn,
);

void main() {
  group('Pakkestatus', () {
    test('manglende sikkerhetsutstyr gir «Ikke klar»', () {
      final items = [
        _item('forstehjelp', PackingCategory.safetyFirstAid),
        _item('sokker', PackingCategory.clothing, packed: true),
      ];
      expect(items.readiness, PackReadiness.notReady);
      expect(items.missingSafetyCount, 1);
    });

    test('bare annet nødvendig mangler gir «Nesten klar»', () {
      final items = [
        _item('kart', PackingCategory.navigation, packed: true),
        _item('sovepose', PackingCategory.shelterSleeping),
      ];
      expect(items.readiness, PackReadiness.almost);
    });

    test('valgfritt og påkledd teller ikke som mangel', () {
      final items = [
        _item(
          'stol',
          PackingCategory.additional,
          priority: PackingPriority.optional,
        ),
        _item('stovler', PackingCategory.clothing, worn: true),
        _item('kart', PackingCategory.navigation, packed: true),
      ];
      expect(items.readiness, PackReadiness.ready);
    });

    test('vekt per kategori utelater påkledd og sorterer tyngst først', () {
      final items = [
        _item('telt', PackingCategory.shelterSleeping, grams: 1800),
        _item('lue', PackingCategory.clothing, grams: 80),
        _item('stovler', PackingCategory.clothing, grams: 1200, worn: true),
        _item('vann', PackingCategory.water, grams: 1000),
      ];
      final rows = items.packWeightByCategory;
      expect(rows.map((r) => r.$1).toList(), [
        PackingCategory.shelterSleeping,
        PackingCategory.water,
        PackingCategory.clothing,
      ]);
      expect(rows.last.$2, 80);
    });
  });

  group('Mitt utstyr', () {
    test('lagres med navn uten dubletter og overlever JSON', () {
      final p = UserProfile(packLimitKg: 14)
        ..rememberGear(
          const OwnedGear(
            name: 'Powerbank',
            category: PackingCategory.navigation,
            unitWeightGrams: 200,
          ),
        )
        ..rememberGear(
          const OwnedGear(
            name: 'powerbank',
            category: PackingCategory.navigation,
            unitWeightGrams: 180,
          ),
        )
        ..rememberGear(
          const OwnedGear(
            name: 'Ullsokker',
            category: PackingCategory.clothing,
            unitWeightGrams: 80,
            worn: true,
          ),
        );
      expect(p.gear.length, 2);
      expect(p.gearNamed('POWERBANK')?.unitWeightGrams, 180);

      final back = UserProfile.decode(p.encode());
      expect(back.packLimitKg, 14);
      expect(back.gear.map((g) => g.name), ['powerbank', 'Ullsokker']);
      expect(back.gearNamed('ullsokker')?.worn, isTrue);
      expect(back.isEmpty, isFalse);
      expect(UserProfile.decode(UserProfile().encode()).gear, isEmpty);
    });
  });
}
