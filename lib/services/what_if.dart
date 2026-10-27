import '../core/format.dart';
import '../models/gear.dart';
import '../models/packing.dart';
import '../models/trip.dart';
import 'gear_catalog.dart';

/// What a piece of gear is for. Coverage is checked per need, so the
/// app can tell whether the pack handles a situation — not just
/// whether a specific product is on the list.
enum TripNeed {
  map,
  light,
  warmth,
  rain,
  dry,
  shelter,
  firstAid,
  call,
  power,
  water,
  food,
  float,
}

extension TripNeedX on TripNeed {
  String get label => switch (this) {
    TripNeed.map => 'Kart og kompass',
    TripNeed.light => 'Lys',
    TripNeed.warmth => 'Ekstra varme',
    TripNeed.rain => 'Regntøy',
    TripNeed.dry => 'Tørt skift',
    TripNeed.shelter => 'Nødly',
    TripNeed.firstAid => 'Førstehjelp',
    TripNeed.call => 'Varsle om hjelp',
    TripNeed.power => 'Strøm til mobilen',
    TripNeed.water => 'Drikke',
    TripNeed.food => 'Ekstra mat',
    TripNeed.float => 'Flytevest',
  };

  /// Catalog entry offered when the need is not covered.
  String get suggestId => switch (this) {
    TripNeed.map => 'map',
    TripNeed.light => 'headlamp',
    TripNeed.warmth => 'midlayer',
    TripNeed.rain => 'shell',
    TripNeed.dry => 'drychange',
    TripNeed.shelter => 'windbag',
    TripNeed.firstAid => 'firstaid',
    TripNeed.call => 'phone',
    TripNeed.power => 'powerbank',
    TripNeed.water => 'bottle',
    TripNeed.food => 'emergencyfood',
    TripNeed.float => 'pfd',
  };

  Set<String> get gearIds => switch (this) {
    TripNeed.map => const {'map', 'mapcase', 'compass'},
    TripNeed.light => const {'headlamp', 'bikelights'},
    TripNeed.warmth => const {'midlayer', 'puffy', 'extrawarm'},
    TripNeed.rain => const {'shell', 'rainpants'},
    TripNeed.dry => const {'drychange', 'kidclothes'},
    TripNeed.shelter => const {'windbag', 'tent', 'tarp', 'wintertent'},
    TripNeed.firstAid => const {'firstaid'},
    TripNeed.call => const {'phone', 'satcomm', 'whistle'},
    TripNeed.power => const {'powerbank'},
    TripNeed.water => const {'bottle', 'waterfilter', 'thermos', 'water-total'},
    TripNeed.food => const {
      'emergencyfood',
      'hutsnacks',
      'hutkitchen',
      'kidsnacks',
      'food-total',
    },
    TripNeed.float => const {'pfd'},
  };

  /// Word prefixes for gear the user typed in themselves.
  List<String> get keywords => switch (this) {
    TripNeed.map => const ['kart', 'kompass'],
    TripNeed.light => const ['hodelykt', 'lommelykt', 'lykt', 'lampe'],
    TripNeed.warmth => const [
      'fleece',
      'dunjakke',
      'fiberjakke',
      'primaloft',
      'isolasjon',
      'varmeplagg',
      'ullgenser',
      'ulljakke',
    ],
    TripNeed.rain => const ['regnjakke', 'regnbukse', 'regntøy', 'skalljakke'],
    TripNeed.dry => const ['skift', 'skiftetøy'],
    TripNeed.shelter => const ['vindsekk', 'bivuakk', 'nødbivuakk', 'telt'],
    TripNeed.firstAid => const ['førstehjelp'],
    TripNeed.call => const ['mobil', 'nødmelder', 'inreach', 'plb', 'fløyte'],
    TripNeed.power => const ['powerbank', 'strømbank', 'ladebank'],
    TripNeed.water => const ['drikkeflaske', 'flaske', 'termos', 'vannfilter'],
    TripNeed.food => const ['nødproviant', 'snacks', 'turmat', 'sjokolade'],
    TripNeed.float => const ['flytevest', 'redningsvest'],
  };
}

final _catalogIds = {for (final g in gearCatalog) g.id};

/// Catalog items are matched by their stable id only (so «Teltpløkker»
/// never counts as a tent); the user's own gear is matched by name.
bool coversNeed(PackingItem item, TripNeed need) {
  if (need.gearIds.contains(item.id)) return true;
  if (_catalogIds.contains(item.id)) return false;
  final words = item.name.toLowerCase().split(RegExp(r'[^a-zæøå0-9]+'));
  return words.any((w) => need.keywords.any(w.startsWith));
}

enum NeedState { packed, listed, missing }

class NeedCheck {
  final TripNeed need;
  final List<PackingItem> items;

  const NeedCheck(this.need, this.items);

  NeedState get state => items.isEmpty
      ? NeedState.missing
      : items.any((i) => i.packed || i.worn)
      ? NeedState.packed
      : NeedState.listed;
}

NeedCheck checkNeed(Iterable<PackingItem> items, TripNeed need) =>
    NeedCheck(need, [
      for (final i in items)
        if (coversNeed(i, need)) i,
    ]);

class WhatIf {
  final String title;
  final String advice;
  final List<NeedCheck> checks;

  const WhatIf({
    required this.title,
    required this.advice,
    required this.checks,
  });

  /// The weakest need decides: one missing need makes the scenario
  /// uncovered.
  NeedState get state => checks.fold(
    NeedState.packed,
    (s, c) => c.state.index > s.index ? c.state : s,
  );

  List<NeedCheck> get missing => [
    for (final c in checks)
      if (c.state == NeedState.missing) c,
  ];
}

/// «Hva hvis?» — the situations that most often turn a normal trip
/// into a rescue, each checked against what is actually on the list.
List<WhatIf> whatIfChecks(Trip trip, TripConditions c) {
  final items = trip.packingList;
  List<NeedCheck> check(List<TripNeed> needs) => [
    for (final n in needs) checkNeed(items, n),
  ];
  final est = trip.totalEstimatedMinutes;
  final paddling =
      c.activity == TripActivity.paddle ||
      c.carry == CarryMode.canoe ||
      c.carry == CarryMode.kayak;

  return [
    WhatIf(
      title: 'Turen tar dobbelt så lang tid',
      advice:
          '${est > 0 ? 'Anslått ${fmtDuration(est)} kan bli ${fmtDuration(est * 2)} med snø, tåke eller en skade. ' : 'Snø, tåke eller en skade kan doble tiden. '}'
          'Avtal en returtid med noen hjemme, og snu i tide.',
      checks: check([
        TripNeed.food,
        TripNeed.water,
        TripNeed.warmth,
        if (c.darkEvenings) TripNeed.light,
      ]),
    ),
    WhatIf(
      title: 'Mobilen går tom',
      advice:
          'Last ned kart før du drar, hold mobilen varm i en innerlomme og '
          'bruk flymodus når du ikke trenger dekning.',
      checks: check([TripNeed.map, TripNeed.power]),
    ),
    WhatIf(
      title: 'Du blir våt og kald',
      advice:
          'Ta på regntøy før du blir våt, skift til tørt før du fryser, og '
          'spis og drikk jevnlig.',
      checks: check([
        TripNeed.rain,
        TripNeed.dry,
        TripNeed.warmth,
        TripNeed.shelter,
      ]),
    ),
    WhatIf(
      title: 'Noen skader seg og dere må vente på hjelp',
      advice:
          'Ring 113 ved fare for liv. Hold den skadde varm og tørr – det kan '
          'ta flere timer før hjelpen kommer.',
      checks: check([
        TripNeed.firstAid,
        TripNeed.call,
        TripNeed.shelter,
        TripNeed.warmth,
      ]),
    ),
    if (paddling)
      WhatIf(
        title: 'Dere velter i vannet',
        advice:
            'Padl nær land når vannet er kaldt, og pakk skift og mobil '
            'vanntett.',
        checks: check([
          TripNeed.float,
          TripNeed.dry,
          TripNeed.warmth,
          TripNeed.call,
        ]),
      ),
  ];
}
