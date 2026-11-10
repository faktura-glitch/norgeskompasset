import '../models/gear.dart';
import '../models/packing.dart';

/// The forecast-driven inputs the packing rules react to.
typedef WeatherBasis = ({
  bool rain,
  bool heavyRain,
  bool strongWind,
  bool storm,
  bool cold,
  double? minTemp,
  bool minTempEstimated,
});

/// What a new forecast changed in the packing list. Shown to the user
/// so they know what to re-check instead of items silently appearing
/// or disappearing.
class PackingChange {
  final DateTime at;

  /// Plain advice tied to the forecast change ("Nedbør meldt – sjekk …").
  final List<String> notes;
  final List<String> added;

  /// Generated items the rules no longer suggest. Packed ones are marked.
  final List<String> removed;

  const PackingChange({
    required this.at,
    this.notes = const [],
    this.added = const [],
    this.removed = const [],
  });

  bool get isEmpty => notes.isEmpty && added.isEmpty && removed.isEmpty;

  static WeatherBasis basisOf(TripConditions c) => (
    rain: c.rain,
    heavyRain: c.heavyRain,
    strongWind: c.strongWind,
    storm: c.storm,
    cold: c.cold,
    minTemp: c.minTemp,
    minTempEstimated: c.minTempEstimated,
  );

  static PackingChange diff({
    required WeatherBasis before,
    required WeatherBasis after,
    required List<PackingItem> oldList,
    required List<PackingItem> newList,
    DateTime? at,
  }) {
    final notes = <String>[];
    if (!before.heavyRain && after.heavyRain) {
      notes.add(
        'Mye regn meldt – sjekk regntøy, ekstra ull og vanntett pakkpose.',
      );
    } else if (!before.rain && after.rain) {
      notes.add('Nedbør meldt – sjekk regntøy og vanntette pakkposer.');
    } else if (before.rain && !after.rain) {
      notes.add('Ikke lenger meldt nedbør – regntøy er likevel lurt å ha med.');
    }
    if (!before.storm && after.storm) {
      notes.add(
        'Stormkast meldt – sjekk at teltet tåler vinden, og ta ekstra barduner.',
      );
    } else if (!before.strongWind && after.strongWind) {
      notes.add(
        'Sterk vind meldt – sjekk vindtett lag, og at teltet tåler vind.',
      );
    } else if (before.strongWind && !after.strongWind) {
      notes.add('Ikke lenger meldt sterk vind.');
    }
    final b = before.minTemp, a = after.minTemp;
    if (b != null && a != null) {
      final estimate = after.minTempEstimated ? ' (estimat med høydekorreksjon)' : '';
      if (a <= b - 2) {
        notes.add(
          'Kaldere enn sist (min ${a.round()} °C$estimate, var ${b.round()} °C) – '
          'sjekk varmelag, lue og votter.',
        );
      } else if (a >= b + 2) {
        notes.add(
          'Mildere enn sist (min ${a.round()} °C$estimate, var ${b.round()} °C).',
        );
      }
    }
    if (!before.cold && after.cold) {
      notes.add('Kuldegrader om natten – sjekk sovepose og liggeunderlag.');
    }

    String key(PackingItem i) => i.name.trim().toLowerCase();
    final oldKeys = {for (final i in oldList) key(i)};
    final newKeys = {for (final i in newList) key(i)};
    return PackingChange(
      at: at ?? DateTime.now(),
      notes: notes,
      added: [
        for (final i in newList)
          if (!oldKeys.contains(key(i))) i.name,
      ],
      removed: [
        for (final i in oldList)
          if (!i.userAdded && !newKeys.contains(key(i)))
            i.packed ? '${i.name} (var pakket)' : i.name,
      ],
    );
  }
}
