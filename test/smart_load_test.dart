import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/packing.dart';
import 'package:norgeskompasset/services/packing_change.dart';
import 'package:norgeskompasset/services/smart_load.dart';

PackingItem _item(
  String name,
  PackingCategory cat, {
  PackingPriority priority = PackingPriority.recommended,
  double grams = 100,
  bool packed = false,
  bool userAdded = false,
}) => PackingItem(
  id: name,
  name: name,
  category: cat,
  unitWeightGrams: grams,
  priority: priority,
  packed: packed,
  userAdded: userAdded,
);

void main() {
  group('SmartLoad', () {
    test('foreslår valgfritt utstyr, aldri nødvendig eller sikkerhet', () {
      final tips = smartLoadSuggestions([
        _item(
          'Stol',
          PackingCategory.additional,
          priority: PackingPriority.optional,
          grams: 500,
        ),
        _item(
          'Telt',
          PackingCategory.shelterSleeping,
          priority: PackingPriority.required,
          grams: 1800,
        ),
        _item(
          'Ekstra kompass',
          PackingCategory.navigation,
          priority: PackingPriority.optional,
          grams: 50,
        ),
        _item(
          'Bok',
          PackingCategory.personal,
          priority: PackingPriority.optional,
          grams: 0,
        ),
      ]);
      expect(tips.map((t) => t.title), ['Stol']);
      expect(tips.single.savedGrams, 500);
    });

    test('overlappende utstyr: beholder det viktigste/letteste', () {
      final tips = smartLoadSuggestions([
        _item('Kniv', PackingCategory.additional, grams: 90),
        _item('Multiverktøy', PackingCategory.additional, grams: 230),
      ]);
      expect(tips, hasLength(1));
      expect(tips.single.remove.single.name, 'Multiverktøy');
      expect(tips.single.detail, contains('Holder det med Kniv?'));
    });

    test('overlapp der den andre er nødvendig foreslås ikke fjernet', () {
      final tips = smartLoadSuggestions([
        _item(
          'Hodelykt',
          PackingCategory.safetyFirstAid,
          priority: PackingPriority.required,
        ),
        _item(
          'Lommelykt',
          PackingCategory.safetyFirstAid,
          priority: PackingPriority.required,
        ),
      ]);
      expect(tips, isEmpty);
    });
  });

  group('Endringer etter nytt værvarsel', () {
    const dry = (
      rain: false,
      heavyRain: false,
      strongWind: false,
      storm: false,
      cold: false,
      minTemp: 8.0,
      minTempEstimated: false,
    );
    test('regn, vind og kulde gir råd om hva som bør sjekkes', () {
      final change = PackingChange.diff(
        before: dry,
        after: (
          rain: true,
          heavyRain: false,
          strongWind: true,
          storm: false,
          cold: true,
          minTemp: -2.0,
          minTempEstimated: false,
        ),
        oldList: [_item('Solkrem', PackingCategory.personal, packed: true)],
        newList: [_item('Regnjakke', PackingCategory.clothing)],
      );
      expect(change.notes.join(' '), contains('regntøy'));
      expect(change.notes.join(' '), contains('vindtett'));
      expect(change.notes.join(' '), contains('Kaldere enn sist'));
      expect(change.notes.join(' '), contains('sovepose'));
      expect(change.added, ['Regnjakke']);
      expect(change.removed, ['Solkrem (var pakket)']);
    });

    test('uendret vær og liste gir ingen endring', () {
      final list = [_item('Kart', PackingCategory.navigation)];
      final change = PackingChange.diff(
        before: dry,
        after: dry,
        oldList: list,
        newList: [_item('kart', PackingCategory.navigation)],
      );
      expect(change.isEmpty, isTrue);
    });

    test('egne gjenstander meldes ikke som fjernet', () {
      final change = PackingChange.diff(
        before: dry,
        after: dry,
        oldList: [
          _item('Kortstokk', PackingCategory.personal, userAdded: true),
        ],
        newList: const [],
      );
      expect(change.removed, isEmpty);
    });
  });
}
