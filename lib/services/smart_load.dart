import '../models/packing.dart';

/// One way to carry less. Only a suggestion — the user approves each.
class LoadSuggestion {
  final String title;
  final String detail;
  final List<PackingItem> remove;

  const LoadSuggestion({
    required this.title,
    required this.detail,
    required this.remove,
  });

  double get savedGrams => remove.fold(0.0, (s, i) => s + i.totalWeightGrams);
}

/// Gear that does the same job. Two of these rarely add safety.
const _overlapFamilies = <String, List<String>>{
  'lyskilder': ['hodelykt', 'lommelykt', 'lykt', 'lampe'],
  'kniver/verktøy': ['kniv', 'multiverktøy', 'multitool'],
  'sitteunderlag': ['sitteunderlag', 'sittepute'],
  'kopper': ['kopp', 'krus'],
  'strømbanker': ['powerbank', 'strømbank', 'ladebank', 'batteripakke'],
};

/// SmartLoad, simple version: finds optional gear and overlapping
/// gear that can stay home. Required items and safety/navigation gear
/// are never suggested removed.
List<LoadSuggestion> smartLoadSuggestions(Iterable<PackingItem> items) {
  bool removable(PackingItem i) =>
      !i.worn &&
      !i.isConsumable &&
      i.priority != PackingPriority.required &&
      !safetyCriticalCategories.contains(i.category) &&
      i.totalWeightGrams > 0;

  final list = items.toList();
  final out = <LoadSuggestion>[];
  final taken = <String>{};

  for (final MapEntry(key: label, value: words) in _overlapFamilies.entries) {
    final group = [
      for (final i in list)
        if (!i.worn && words.any(i.name.toLowerCase().contains)) i,
    ];
    if (group.length < 2) continue;
    // Keep the most important one; among equals, the lightest.
    group.sort((a, b) {
      final p = a.priority.index.compareTo(b.priority.index);
      return p != 0 ? p : a.totalWeightGrams.compareTo(b.totalWeightGrams);
    });
    final keep = group.first;
    final extra = group.skip(1).where(removable).toList();
    if (extra.isEmpty) continue;
    taken.addAll(extra.map((i) => i.id));
    out.add(
      LoadSuggestion(
        title: '${group.length} $label',
        detail:
            'Du har ${group.map((i) => i.name).join(', ')}. '
            'Holder det med ${keep.name}?',
        remove: extra,
      ),
    );
  }

  for (final i in list) {
    if (taken.contains(i.id) ||
        i.priority != PackingPriority.optional ||
        !removable(i)) {
      continue;
    }
    out.add(
      LoadSuggestion(
        title: i.name,
        detail: i.reason == null
            ? 'Valgfritt – kan bli hjemme.'
            : 'Valgfritt (${i.reason}) – kan bli hjemme.',
        remove: [i],
      ),
    );
  }
  out.sort((a, b) => b.savedGrams.compareTo(a.savedGrams));
  return out;
}
