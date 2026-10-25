import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/packing.dart';
import '../models/planning_context.dart';
import '../models/trip.dart';
import '../services/gear_catalog.dart';
import '../services/planning_context.dart';
import '../services/packing_engine.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

enum _Filter { all, recommended, missing, packed, inPack, worn, acquire }

class PackingScreen extends StatefulWidget {
  const PackingScreen({super.key});

  @override
  State<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends State<PackingScreen> {
  _Filter _filter = _Filter.all;
  String _search = '';
  PackingCategory? _category;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, List<Object?>>(
      (s) => [
        s.currentTripId,
        s.currentTrip?.name,
        for (final item in s.currentTrip?.packingList ?? <PackingItem>[])
          (
            item.id,
            item.name,
            item.category,
            item.quantity,
            item.unitWeightGrams,
            item.packed,
            item.worn,
            item.priority,
            item.reason,
            item.needsAcquisition,
          ),
      ],
    );
    final state = context.read<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    return Scaffold(
      appBar: AppBar(
        title: tripScreenTitle('Pakkeliste', trip),
        actions: [
          if (trip != null)
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Pakkeforhåndsvalg',
              onPressed: () => _presetsSheet(context, trip),
            ),
          if (trip != null)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Maler',
              onPressed: () => _templatesSheet(context, trip),
            ),
          if (trip != null)
            PopupMenuButton<String>(
              onSelected: (v) => _menu(v, trip),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'generate',
                  child: Text('Generer liste på nytt'),
                ),
                PopupMenuItem(value: 'optimize', child: Text('Optimaliser')),
              ],
            ),
        ],
      ),
      body: trip == null
          ? EmptyState(
              icon: Icons.checklist,
              title: 'Ingen tur valgt',
              message: 'Opprett eller velg en tur for å bruke pakkelisten.',
            )
          : trip.packingList.isEmpty
          ? _GeneratePrompt(trip: trip)
          : _PackingBody(
              trip: trip,
              wide: wide,
              filter: _filter,
              search: _search,
              category: _category,
              onFilter: (f) => setState(() => _filter = f),
              searchController: _searchController,
              onSearch: (s) {
                if (s.isEmpty) _searchController.clear();
                setState(() => _search = s);
              },
              onCategory: (c) => setState(() => _category = c),
            ),
      floatingActionButton: trip?.packingList.isNotEmpty == true
          ? FloatingActionButton(
              heroTag: 'fab-packing',
              onPressed: () => _addItem(context, trip!),
              backgroundColor: NkColors.forestGreen,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _menu(String v, Trip trip) async {
    final state = context.read<AppState>();
    if (v == 'generate') {
      final ok = await _confirm(
        context,
        'Generer på nytt?',
        'Listen bygges opp på nytt basert på tur, vær og overnatting. '
            'Pakket-status og egne gjenstander beholdes.',
      );
      if (ok) await state.generatePackingList(trip);
    } else if (v == 'optimize') {
      final engine = PackingEngine();
      final notes = engine.describeOptimization(trip);
      final ok = await _confirm(
        context,
        'Optimaliser pakkeliste',
        notes.join('\n\n'),
      );
      if (ok) {
        final removed = engine.optimize(trip);
        await state.saveTrip(trip);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                removed > 0
                    ? 'Slo sammen $removed duplikat(er).'
                    : 'Ingen endringer var nødvendige.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _templatesSheet(BuildContext context, Trip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TemplatesSheet(trip: trip),
    );
  }

  /// Lets the user pick a trip preset. The preset only sets activity,
  /// carry, accommodation and season — the rule matrix then decides
  /// every item, so the result can be tweaked afterwards.
  Future<void> _presetsSheet(BuildContext context, Trip trip) async {
    final state = context.read<AppState>();
    final preset = await showModalBottomSheet<PackingPreset>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Velg et utgangspunkt – aktivitet, bæring, overnatting '
                'og sesong settes om. Reglene for utstyr kan fortsatt '
                'justeres i etterkant.',
              ),
            ),
            for (final p in packingPresets)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(p.name),
                subtitle: Text(
                  '${p.description}\n${p.activity.label} · ${p.carry.label} · '
                  '${p.accommodation.label} · ${p.season.label}',
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (preset == null || !mounted) return;
    if (trip.packingList.isNotEmpty) {
      final ok = await _confirm(
        this.context,
        'Bruk «${preset.name}»?',
        'Aktivitet, bæring, overnatting og sesong endres, og pakkelisten '
            'genereres på nytt. Pakket-status, egne gjenstander og justerte '
            'vekter beholdes.',
      );
      if (!ok || !mounted) return;
    }
    await state.applyPackingPreset(trip, preset);
  }

  void _addItem(BuildContext context, Trip trip) {
    final name = TextEditingController();
    final weight = TextEditingController();
    PackingCategory cat = PackingCategory.additional;
    var worn = false;
    var needsAcquisition = false;
    String? weightError;
    String? nameError;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ny gjenstand'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Navn',
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weight,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Vekt per stk (gram)',
                    errorText: weightError,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PackingCategory>(
                  initialValue: cat,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    for (final c in PackingCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) => setD(() => cat = v!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Bæres på kroppen',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'F.eks. skoene du går i – telles ikke i sekkvekta',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: worn,
                  onChanged: (v) => setD(() => worn = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Må lånes eller skaffes'),
                  value: needsAcquisition,
                  onChanged: (v) => setD(() => needsAcquisition = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () async {
                final grams = weight.text.trim().isEmpty
                    ? 0.0
                    : double.tryParse(weight.text.trim().replaceAll(',', '.'));
                setD(() {
                  nameError = name.text.trim().isEmpty ? 'Skriv et navn' : null;
                  weightError = grams == null || !grams.isFinite || grams < 0
                      ? 'Oppgi en gyldig vekt i gram'
                      : null;
                });
                if (nameError != null || weightError != null || grams == null) {
                  return;
                }
                trip.packingList.add(
                  PackingItem(
                    id: const Uuid().v4().substring(0, 8),
                    name: name.text.trim(),
                    category: cat,
                    unitWeightGrams: grams,
                    worn: worn,
                    needsAcquisition: needsAcquisition,
                    userAdded: true,
                  ),
                );
                await context.read<AppState>().saveTrip(trip);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Legg til'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratePrompt extends StatelessWidget {
  final Trip trip;
  const _GeneratePrompt({required this.trip});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: const ScenicImage(
              url: NkImages.hardangerviddaTent,
              height: 170,
              overlayOpacity: 0.3,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Teltvidda, Hardangervidda',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(
            Icons.luggage_outlined,
            size: 40,
            color: NkColors.primaryBlue,
          ),
          const SizedBox(height: 10),
          const Text(
            'Ingen pakkeliste ennå',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Generer en pakkeliste tilpasset turens lengde, overnatting, årstid og værprognose.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => context.read<AppState>().generatePackingList(trip),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generer pakkeliste'),
          ),
        ],
      ),
    );
  }
}

class _PackingBody extends StatelessWidget {
  final Trip trip;
  final bool wide;
  final _Filter filter;
  final String search;
  final PackingCategory? category;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<String> onSearch;
  final TextEditingController searchController;
  final ValueChanged<PackingCategory?> onCategory;

  const _PackingBody({
    required this.trip,
    required this.wide,
    required this.filter,
    required this.search,
    required this.category,
    required this.onFilter,
    required this.onSearch,
    required this.searchController,
    required this.onCategory,
  });

  List<PackingItem> _filtered() {
    var items = trip.packingList;
    switch (filter) {
      case _Filter.all:
        break;
      case _Filter.recommended:
        items = items
            .where((i) => i.priority != PackingPriority.optional)
            .toList();
      case _Filter.missing:
        items = items.where((i) => !i.packed).toList();
      case _Filter.packed:
        items = items.where((i) => i.packed).toList();
      case _Filter.inPack:
        items = items.where((i) => !i.worn).toList();
      case _Filter.worn:
        items = items.where((i) => i.worn).toList();
      case _Filter.acquire:
        items = items.where((i) => i.needsAcquisition).toList();
    }
    if (category != null) {
      items = items.where((i) => i.category == category).toList();
    }
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      items = items.where((i) => i.name.toLowerCase().contains(q)).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    final grouped = <PackingCategory, List<PackingItem>>{};
    for (final i in items) {
      grouped.putIfAbsent(i.category, () => []).add(i);
    }

    return Column(
      children: [
        _Header(
          trip: trip,
          filter: filter,
          onFilter: onFilter,
          onSearch: onSearch,
          searchController: searchController,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _catChip(null, 'Alle', onCategory),
                for (final c in PackingCategory.values)
                  _catChip(c, c.label, onCategory),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            // Extra bottom padding so the last item clears the FAB —
            // the + button must never cover an item's weight.
            padding: EdgeInsets.fromLTRB(
              wide ? 28 : 16,
              wide ? 28 : 16,
              wide ? 28 : 16,
              96,
            ),
            children: [
              _PlanningBasis(trip: trip),
              if (trip.deletedGearIds.isNotEmpty)
                _HiddenSuggestions(trip: trip),
              // Legend — new users shouldn't have to guess what the
              // colored dots next to item names mean.
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 12,
                  children: [
                    for (final (c, l) in [
                      (NkColors.dangerRed, 'Nødvendig'),
                      (NkColors.primaryBlue, 'Anbefalt'),
                      (NkColors.textSecondary, 'Valgfri'),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l,
                            style: TextStyle(
                              fontSize: 10,
                              color: NkColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              for (final entry in grouped.entries) ...[
                _CategorySection(
                  category: entry.key,
                  items: entry.value,
                  trip: trip,
                ),
                const SizedBox(height: 12),
              ],
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    children: [
                      const Text('Ingen gjenstander matcher filteret'),
                      TextButton(
                        onPressed: () {
                          onFilter(_Filter.all);
                          onCategory(null);
                          onSearch('');
                        },
                        child: const Text('Nullstill filtre'),
                      ),
                    ],
                  ),
                ),
              const Text(
                'Ikke pakket betyr ikke at utstyret mangler hjemme. '
                'Se merknadene for utstyr som må lånes eller skaffes.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _catChip(
    PackingCategory? c,
    String label,
    ValueChanged<PackingCategory?> onSel,
  ) {
    final active = category == c;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: active,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onSel(active ? null : c),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Trip trip;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<String> onSearch;
  final TextEditingController searchController;

  const _Header({
    required this.trip,
    required this.filter,
    required this.onFilter,
    required this.onSearch,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    final items = trip.packingList;
    final worn = items
        .where((i) => i.worn)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    final equipment = items
        .where((i) => !i.isConsumable && !i.worn)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    final food = items
        .where((i) => i.category == PackingCategory.food)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    final water = items
        .where((i) => i.category == PackingCategory.water)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    // Base weight = carried equipment that isn't consumed on the trip.
    // Start weight = base + food, water, fuel and other consumables.
    final consumables = items
        .where((i) => i.isConsumable && !i.worn)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    // Weight-based progress counts only what goes INTO the pack —
    // worn items (boots, hiking clothes) never sit in the pack, so
    // they shouldn't hold back the progress ring or "igjen i sekken".
    final packItems = items.where((i) => !i.worn).toList();
    final totalGrams = packItems.fold(0.0, (s, i) => s + i.totalWeightGrams);
    final packedGrams = packItems
        .where((i) => i.packed)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    final weightProgress = totalGrams > 0 ? packedGrams / totalGrams : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.isWide ? 28 : 16,
        12,
        context.isWide ? 28 : 16,
        8,
      ),
      child: Column(
        children: [
          NkCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Circular packed counter — by weight, not count
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: weightProgress,
                            strokeWidth: 7,
                            backgroundColor: NkColors.border,
                            valueColor: const AlwaysStoppedAnimation(
                              NkColors.forestGreen,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fmtWeight(packedGrams),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: NkColors.forestGreen,
                                ),
                              ),
                              Text(
                                'av ${fmtWeight(totalGrams)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: NkColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(weightProgress * 100).round()} % av vekten pakket',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${fmtWeight(totalGrams - packedGrams)} igjen i sekken'
                            '${trip.missingRequiredCount > 0 ? '  ·  ${trip.missingRequiredCount} nødvendige!' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: trip.missingRequiredCount > 0
                                  ? NkColors.dangerRed
                                  : NkColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Grunnvekt: ${fmtWeight(equipment)}'
                            '  ·  Startvekt: ${fmtWeight(equipment + consumables)}'
                            '${worn > 0 ? '  ·  På kroppen: ${fmtWeight(worn)}' : ''}'
                            '${food > 0 || consumables > food + water ? '  ·  (forbruksvarer ${fmtWeight(consumables)}${food > 0 ? ', herav mat ${fmtWeight(food)}' : ''}${water > 0 ? ' + vann ${fmtWeight(water)}' : ''})' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: NkColors.textSecondary,
                            ),
                          ),
                          Text(
                            'Total bærevekt (estimert): ${fmtWeight(equipment + consumables + worn)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: NkColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                NkProgress(weightProgress),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (f, label) in [
                  (_Filter.all, 'Alt'),
                  (_Filter.inPack, 'I sekken'),
                  (_Filter.worn, 'På kroppen'),
                  (_Filter.recommended, 'Anbefalt'),
                  (_Filter.missing, 'Ikke pakket'),
                  (_Filter.packed, 'Pakket'),
                  (_Filter.acquire, 'Må skaffes'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: filter == f,
                      onSelected: (_) => onFilter(f),
                    ),
                  ),
              ],
            ),
          ),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Søk i pakkelisten',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onSearch,
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatefulWidget {
  final PackingCategory category;
  final List<PackingItem> items;
  final Trip trip;

  const _CategorySection({
    required this.category,
    required this.items,
    required this.trip,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final weight = items.fold(0.0, (s, i) => s + i.totalWeightGrams);
    final packed = items.where((i) => i.packed).length;
    return NkCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.category.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$packed/${items.length} · ${fmtWeight(weight)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: NkColors.textSecondary,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: NkColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            for (final item in items) _ItemRow(item: item, trip: widget.trip),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final PackingItem item;
  final Trip trip;
  const _ItemRow({required this.item, required this.trip});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Dismissible(
      key: Key(item.id + item.name),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (item.priority == PackingPriority.required) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Fjern nødvendig utstyr?'),
              content: Text(
                '«${item.name}» er merket som nødvendig${item.reason != null ? ' – ${item.reason}' : ''}. '
                'Er du sikker på at du vil fjerne den?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Behold'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: NkColors.dangerRed,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Fjern'),
                ),
              ],
            ),
          );
          return ok == true;
        }
        return true;
      },
      onDismissed: (_) async {
        final idx = trip.packingList.indexWhere((i) => i.id == item.id);
        trip.packingList.removeWhere((i) => i.id == item.id);
        // Tombstone generated suggestions so they don't reappear on
        // the next regeneration — user-added items are simply gone.
        if (!item.userAdded) trip.deletedGearIds.add(item.id);
        await state.saveTrip(trip);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('«${item.name}» fjernet'),
              action: SnackBarAction(
                label: 'Angre',
                onPressed: () {
                  trip.deletedGearIds.remove(item.id);
                  trip.packingList.insert(
                    idx.clamp(0, trip.packingList.length),
                    item,
                  );
                  state.saveTrip(trip);
                },
              ),
            ),
          );
        }
      },
      background: Container(
        color: NkColors.dangerRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: InkWell(
        onTap: () => _editItem(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: item.packed,
                activeColor: NkColors.forestGreen,
                onChanged: (v) async {
                  item.packed = v ?? false;
                  await state.updatePackingItem(trip, item);
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name +
                                (item.quantity > 1
                                    ? ' ×${item.quantity.toStringAsFixed(0)}'
                                    : ''),
                            style: TextStyle(
                              fontSize: 13,
                              decoration: item.packed
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.packed
                                  ? NkColors.textSecondary
                                  : NkColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _priorityDot(item.priority),
                        if (item.worn) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                'Bæres på kroppen – telles ikke i sekkvekta',
                            child: Icon(
                              Icons.accessibility_new,
                              size: 13,
                              color: NkColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.needsAcquisition)
                      const Text(
                        'Må lånes eller skaffes',
                        style: TextStyle(
                          color: NkColors.dangerRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (item.reason != null)
                      Text(
                        item.reason!,
                        style: TextStyle(
                          fontSize: 10,
                          color: NkColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                fmtWeight(item.totalWeightGrams),
                style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.copy_outlined,
                  size: 15,
                  color: NkColors.textSecondary,
                ),
                tooltip: 'Dupliser',
                onPressed: () async {
                  trip.packingList.add(
                    PackingItem(
                      id: const Uuid().v4().substring(0, 8),
                      name: '${item.name} (kopi)',
                      category: item.category,
                      quantity: item.quantity,
                      unitWeightGrams: item.unitWeightGrams,
                      priority: item.priority,
                      worn: item.worn,
                      needsAcquisition: item.needsAcquisition,
                      reason: item.reason,
                      userAdded: true,
                    ),
                  );
                  await state.saveTrip(trip);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityDot(PackingPriority p) {
    final (color, label) = switch (p) {
      PackingPriority.required => (NkColors.dangerRed, 'Nødvendig'),
      PackingPriority.recommended => (NkColors.primaryBlue, 'Anbefalt'),
      PackingPriority.optional => (NkColors.textSecondary, 'Valgfri'),
    };
    return Tooltip(
      message: label,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  void _editItem(BuildContext context) {
    final name = TextEditingController(text: item.name);
    final qty = TextEditingController(text: item.quantity.toStringAsFixed(0));
    final weight = TextEditingController(
      text: item.unitWeightGrams.toStringAsFixed(0),
    );
    var prio = item.priority;
    var worn = item.worn;
    var needsAcquisition = item.needsAcquisition;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Rediger gjenstand'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Navn'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Antall'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: weight,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Vekt/stk (g)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PackingPriority>(
                  initialValue: prio,
                  decoration: const InputDecoration(labelText: 'Prioritet'),
                  items: [
                    for (final p in PackingPriority.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) => setD(() => prio = v!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Bæres på kroppen',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'F.eks. skoene du går i – telles ikke i sekkvekta',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: worn,
                  onChanged: (v) => setD(() => worn = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Må lånes eller skaffes'),
                  value: needsAcquisition,
                  onChanged: (v) => setD(() => needsAcquisition = v),
                ),
              ],
            ),
          ),
          actions: [
            if (!item.userAdded &&
                (item.nameEdited ||
                    item.quantityEdited ||
                    item.priorityEdited ||
                    item.weightEdited))
              TextButton(
                onPressed: () async {
                  item.nameEdited = false;
                  item.quantityEdited = false;
                  item.priorityEdited = false;
                  item.weightEdited = false;
                  await context.read<AppState>().generatePackingList(trip);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Bruk turens forslag'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () async {
                final newName = name.text.trim();
                final newQty = double.tryParse(qty.text.replaceAll(',', '.'));
                final newWeight = double.tryParse(
                  weight.text.replaceAll(',', '.'),
                );
                if (newName.isEmpty ||
                    newQty == null ||
                    !newQty.isFinite ||
                    newQty <= 0 ||
                    newWeight == null ||
                    !newWeight.isFinite ||
                    newWeight < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Skriv navn, antall over 0 og vekt fra 0 gram.',
                      ),
                    ),
                  );
                  return;
                }
                if (!item.userAdded) {
                  item.nameEdited |= item.name != newName;
                  item.quantityEdited |= item.quantity != newQty;
                  item.priorityEdited |= item.priority != prio;
                  item.weightEdited |= item.unitWeightGrams != newWeight;
                }
                item.name = newName;
                item.quantity = newQty;
                item.unitWeightGrams = newWeight;
                item.priority = prio;
                item.worn = worn;
                item.needsAcquisition = needsAcquisition;
                await context.read<AppState>().updatePackingItem(trip, item);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplatesSheet extends StatelessWidget {
  final Trip trip;
  const _TemplatesSheet({required this.trip});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final templates = state.repo.loadTemplates();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pakkemaler',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                final ctrl = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Lagre mal'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(labelText: 'Malnavn'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Avbryt'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                        child: const Text('Lagre'),
                      ),
                    ],
                  ),
                );
                if (name != null && name.isNotEmpty) {
                  await state.repo.saveTemplate(name, trip.packingList);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Lagre nåværende liste som mal'),
            ),
            const SizedBox(height: 14),
            if (templates.isEmpty)
              Text(
                'Ingen lagrede maler ennå.',
                style: TextStyle(color: NkColors.textSecondary),
              )
            else
              for (final t in templates)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(t['name'] as String),
                  subtitle: Text('${(t['items'] as List).length} gjenstander'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final items = (t['items'] as List)
                              .map(
                                (j) => PackingItem.fromJson(
                                  Map<String, dynamic>.from(j),
                                ),
                              )
                              .toList();
                          await state.applyTemplate(trip, items);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Bruk'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await state.repo.deleteTemplate(t['name']);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// The derived bridge between route/conditions and this list — shows
/// the user exactly what the engine filtered on (route facts, weather
/// state, avalanche basis) plus honest gaps to verify before trusting
/// the plan. Never presents estimates as verified data.
class _PlanningBasis extends StatelessWidget {
  final Trip trip;
  const _PlanningBasis({required this.trip});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    final ctx = PlanningContextBuilder.forTrip(trip, profile);
    final facts = <String>[
      '${ctx.activity.label} · ${ctx.carry.label}',
      if (ctx.distanceKm != null)
        '${ctx.distanceKm!.toStringAsFixed(1)} km'
            '${ctx.totalAscentM != null ? ' · ${ctx.totalAscentM!.round()} m stigning' : ''}'
      else
        ctx.routeLabel,
      ctx.weatherLabel +
          (ctx.minTempC != null ? ' (min ${ctx.minTempC!.round()} °C)' : ''),
      ctx.avalancheBasis.label +
          (ctx.maxDangerLevel != null
              ? ' (faregrad ${ctx.maxDangerLevel})'
              : ''),
    ];
    final warning =
        ctx.userChecks.isNotEmpty ||
        ctx.weatherQuality != DataQuality.good ||
        ctx.hasEstimatedLegs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NkCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 14,
                  color: warning ? NkColors.warningAmber : NkColors.forestGreen,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Grunnlag for listen',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              facts.join('  ·  '),
              style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
            ),
            for (final check in ctx.userChecks) ...[
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('– ', style: TextStyle(color: NkColors.warningAmber)),
                  Expanded(
                    child: Text(
                      check,
                      style: TextStyle(
                        fontSize: 11,
                        color: NkColors.warningAmber,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Restores generated suggestions the user dismissed. Tombstones are
/// listed by name and can be re-included one by one; restoring food/
/// water aggregates resyncs them from the meal plan.
class _HiddenSuggestions extends StatelessWidget {
  final Trip trip;
  const _HiddenSuggestions({required this.trip});

  String _nameFor(String id) {
    for (final g in gearCatalog) {
      if (g.id == id) return g.name;
    }
    return switch (id) {
      'food-total' => 'Mat og drikke (generert)',
      'water-total' => 'Vann (generert)',
      _ => id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.visibility_outlined, size: 16),
        label: Text(
          '${trip.deletedGearIds.length} skjulte forslag – vis og gjenopprett',
          style: const TextStyle(fontSize: 12),
        ),
        onPressed: () async {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Skjulte forslag'),
              content: SizedBox(
                width: 320,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final id in trip.deletedGearIds)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_nameFor(id)),
                        subtitle: const Text(
                          'Fjernet – kommer ikke tilbake automatisk',
                          style: TextStyle(fontSize: 11),
                        ),
                        trailing: TextButton(
                          child: const Text('Ta med igjen'),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            trip.deletedGearIds.remove(id);
                            if (id == 'food-total' || id == 'water-total') {
                              await state.updateMealPlan(trip);
                            } else {
                              await state.generatePackingList(trip);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Lukk'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
