import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../models/food_menu.dart';
import '../models/meal.dart';
import '../models/trip.dart';
import '../services/food_menu_catalog.dart';
import '../state/app_state.dart';

Future<void> showFoodMenuPicker(BuildContext context, Trip trip) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: FoodMenuPicker(trip: trip),
      ),
    );

class FoodMenuPicker extends StatefulWidget {
  final Trip trip;
  const FoodMenuPicker({super.key, required this.trip});

  @override
  State<FoodMenuPicker> createState() => _FoodMenuPickerState();
}

class _FoodMenuPickerState extends State<FoodMenuPicker> {
  String _query = '';
  String _tag = 'Alle';
  int _day = 0;
  bool _compatibleOnly = true;
  bool _applying = false;

  Future<void> _apply(FoodMenu menu) async {
    final trip = widget.trip;
    final state = context.read<AppState>();
    final day = _day == 0 ? null : _day;
    final existing =
        trip.mealPlan?.meals.any((m) => day == null || m.day == day) ?? false;
    if (existing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erstatt måltidene?'),
          content: Text(
            'Menyen erstatter måltidene ${day == null ? 'på alle turdagene' : 'på dag $day'}. '
            'Egne måltider på andre dager beholdes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bruk meny'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (state.currentTrip?.id != trip.id) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Valgt tur er endret. Åpne menyvelgeren på nytt.'),
          ),
        );
      }
      return;
    }
    setState(() => _applying = true);
    try {
      await state.applyFoodMenu(trip, menu, day: day);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('«${menu.name}» er lagt til i matplan og pakkevekt.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kunne ikke bruke menyen. Sjekk kostholdsvalg og prøv igjen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    final preferences = widget.trip.mealPlan?.dietaryPreferences ?? <String>[];
    final hasRestrictions =
        profile.dietTags.isNotEmpty || preferences.isNotEmpty;
    final tags = (foodMenus.expand((m) => m.tags).toSet().toList()..sort());
    final menus = foodMenus
        .where(
          (menu) =>
              (_tag == 'Alle' || menu.tags.contains(_tag)) &&
              (menu.name.toLowerCase().contains(_query.toLowerCase()) ||
                  menu.meals.any(
                    (m) => m.name.toLowerCase().contains(_query.toLowerCase()),
                  )) &&
              (!_compatibleOnly ||
                  menu.conflictsWith(profile, preferences).isEmpty),
        )
        .toList();
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Velg matmeny',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'For «${widget.trip.name}» · menyene er per person og hel dag',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mengder og kalorier er estimater, ikke verifiserte næringsverdier. '
                    'Vann til tilberedning, brensel og emballasje kommer i tillegg. '
                    'Kontroller alltid ingredienser, spor av allergener og oppbevaring.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Søk i matmenyer',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _tag,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      for (final tag in ['Alle', ...tags])
                        DropdownMenuItem(value: tag, child: Text(tag)),
                    ],
                    onChanged: _applying
                        ? null
                        : (value) => setState(() => _tag = value ?? 'Alle'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _day,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Bruk menyen på',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Alle dager i turen'),
                      ),
                      for (var i = 1; i <= widget.trip.hikingDays; i++)
                        DropdownMenuItem(value: i, child: Text('Dag $i')),
                    ],
                    onChanged: _applying
                        ? null
                        : (value) => setState(() => _day = value ?? 0),
                  ),
                  if (hasRestrictions)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Skjul menyer med oppførte kostholdskonflikter',
                      ),
                      subtitle: const Text(
                        'Dette er et filter, ikke en garanti for allergisikker mat.',
                      ),
                      value: _compatibleOnly,
                      onChanged: (value) =>
                          setState(() => _compatibleOnly = value),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '${menus.length} av ${foodMenus.length} menyer · trykk for å se måltidene',
                  ),
                  if (_applying) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          if (menus.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Ingen menyer matcher søket, kategorien og kostholdsvalgene. '
                  'Endre søk eller kategori, eller lag egne måltider i matplanen.',
                ),
              ),
            ),
          SliverList.builder(
            itemCount: menus.length,
            itemBuilder: (_, index) {
              final menu = menus[index];
              final conflicts = menu.conflictsWith(profile, preferences);
              return Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ExpansionTile(
                  key: ValueKey(menu.id),
                  title: Text(menu.name),
                  subtitle: Text(
                    '${fmtWeight(menu.totalWeightGrams)} · ca. ${menu.totalCalories.round()} kcal per person/dag',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final tag in menu.tags) Chip(label: Text(tag)),
                      ],
                    ),
                    for (final meal in menu.meals)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${meal.type.label}: ${meal.name}'),
                            Text(
                              '${meal.weightGrams.round()} g · ca. ${meal.calories.round()} kcal',
                            ),
                          ],
                        ),
                      ),
                    if (menu.needsCooling)
                      const Text(
                        'Inneholder ferskvarer. Planlegg forsvarlig kjøling.',
                      ),
                    if (menu.allergens.isNotEmpty)
                      Text(
                        'Oppførte allergener (ikke uttømmende): ${menu.allergens.join(', ')}',
                      ),
                    if (menu.note != null) Text(menu.note!),
                    if (conflicts.isNotEmpty)
                      Text('Kostholdskonflikt: ${conflicts.join('. ')}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _applying || conflicts.isNotEmpty
                          ? null
                          : () => _apply(menu),
                      icon: const Icon(Icons.check),
                      label: Text(
                        _day == 0
                            ? 'Bruk meny på alle dager'
                            : 'Bruk meny på dag $_day',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
