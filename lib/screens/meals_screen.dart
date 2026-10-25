import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/energy.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/meal.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/food_menu_picker.dart';
import '../services/food_menu_catalog.dart';

class MealsScreen extends StatelessWidget {
  const MealsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    return Scaffold(
      appBar: AppBar(
        title: tripScreenTitle('Matplan', trip),
        actions: [
          if (trip != null)
            IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'Velg matmeny',
              onPressed: () => showFoodMenuPicker(context, trip),
            ),
          if (trip != null && trip.mealPlan != null) ...[
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              tooltip: 'Handleliste',
              onPressed: () => _shoppingList(context, trip),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Generer matplan på nytt',
              onPressed: () => _regenerate(context, trip),
            ),
          ],
        ],
      ),
      body: trip == null
          ? const EmptyState(
              icon: Icons.restaurant_outlined,
              title: 'Ingen tur valgt',
              message: 'Velg en tur for å planlegge måltider.',
            )
          : _Body(trip: trip, wide: wide),
    );
  }

  void _shoppingList(BuildContext context, Trip trip) {
    final list = trip.mealPlan?.shoppingList ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ShoppingListSheet(list: list, trip: trip),
    );
  }

  Future<void> _regenerate(BuildContext context, Trip trip) async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generer matplan på nytt?'),
        content: const Text(
          'Vil du beholde egne måltider og endringer? Kontroller allergier og mengder etterpå.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Erstatt alt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Behold egne valg'),
          ),
        ],
      ),
    );
    if (keep == null || !context.mounted) return;
    final own =
        trip.mealPlan?.meals.where((m) => m.userEdited).toList() ??
        <PlannedMeal>[];
    final state = context.read<AppState>();
    await state.generateMealPlan(trip);
    if (keep && trip.mealPlan != null) {
      final plan = trip.mealPlan!;
      final valid = own.where((m) => m.day <= plan.days).toList();
      plan.meals.removeWhere(
        (m) => valid.any((o) => o.day == m.day && o.type == m.type),
      );
      plan.meals.addAll(valid);
      await state.updateMealPlan(trip);
    }
  }
}

/// Shopping list with real checkboxes (session state) and a
/// copy-to-clipboard action so it can be taken to the store.
class _ShoppingListSheet extends StatefulWidget {
  final List<String> list;
  final Trip trip;
  const _ShoppingListSheet({required this.list, required this.trip});

  @override
  State<_ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<_ShoppingListSheet> {
  Set<String> get _checked => widget.trip.mealPlan!.checkedShoppingItems;

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Handleliste',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (list.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: list.map((e) => '- $e').join('\n')),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Handleliste kopiert')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Kopier'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (list.isEmpty)
              const Text('Ingen måltider planlagt ennå.')
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (_, i) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _checked.contains(list[i]),
                    onChanged: (v) async {
                      setState(
                        () => v == true
                            ? _checked.add(list[i])
                            : _checked.remove(list[i]),
                      );
                      await context.read<AppState>().saveTrip(widget.trip);
                    },
                    title: Text(
                      list[i],
                      style: TextStyle(
                        fontSize: 13,
                        decoration: _checked.contains(list[i])
                            ? TextDecoration.lineThrough
                            : null,
                        color: _checked.contains(list[i])
                            ? NkColors.textSecondary
                            : NkColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Trip trip;
  final bool wide;
  const _Body({required this.trip, required this.wide});

  @override
  Widget build(BuildContext context) {
    final plan = trip.mealPlan;
    if (plan == null) {
      return EmptyState(
        icon: Icons.restaurant_menu_outlined,
        title: 'Ingen matplan',
        message:
            'Generer en enkel matplan for ${fmtCount(trip.hikingDays, 'dag', 'dager')} og ${fmtCount(trip.participants, 'person', 'personer')}. Grammene er omtrentlige – juster etter appetitt og aktivitet.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => showFoodMenuPicker(context, trip),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Velg matmeny'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.read<AppState>().generateMealPlan(trip),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Lag automatisk matplan'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        ScreenBanner(
          url: NkImages.primusStove,
          title: 'Mat og energi på tur',
          subtitle:
              'for «${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» — måltider, vekt og energibehov',
          height: 100,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => showFoodMenuPicker(context, trip),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Velg eller bytt matmeny'),
        ),
        const SizedBox(height: 12),
        Text(
          '${trip.name} · ${fmtCount(plan.days, 'dag', 'dager')} · ${fmtCount(plan.people, 'person', 'personer')}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) =>
                _ShoppingListSheet(list: plan.shoppingList, trip: trip),
          ),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('Åpne handleliste'),
        ),
        const Text(
          'Allergivalg er veiledende. Kontroller alltid ingredienser og spor av allergener.',
        ),
        const SizedBox(height: 12),
        _SummaryCard(trip: trip, plan: plan),
        const SizedBox(height: 14),
        for (var day = 1; day <= plan.days; day++) ...[
          _DayCard(trip: trip, plan: plan, day: day),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        NkCard(
          padding: EdgeInsets.all(12),
          child: Text(
            'Vekt, mengder og kalorier er grovestimater – juster etter eget behov, appetitt og aktivitetsnivå. Aktive turdager krever ofte 3000–4000 kcal eller mer. Sjekk alltid at du har nødproviant utover planen.',
            style: TextStyle(
              fontSize: 11,
              color: NkColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Trip trip;
  final MealPlan plan;
  const _SummaryCard({required this.trip, required this.plan});

  @override
  Widget build(BuildContext context) {
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader('Oversikt', icon: Icons.summarize),
              ),
              TextButton.icon(
                onPressed: () => _settings(context),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Innstillinger'),
              ),
            ],
          ),
          Text(
            'for «${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» — aktiv tur',
            style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              InfoTile('Dager', '${plan.days}'),
              InfoTile('Personer', '${plan.people}'),
              InfoTile('Måltider', '${plan.meals.length}'),
              InfoTile('Matvekt totalt', fmtWeight(plan.totalFoodWeightGrams)),
              InfoTile(
                'Vann (estimert)',
                fmtWeight(plan.totalWaterWeightGrams),
              ),
              if (plan.totalKcalPerPerson > 0) ...[
                InfoTile(
                  'Planlagt mat/dag per pers. (snitt)',
                  '${(plan.totalKcalPerPerson / (plan.days > 0 ? plan.days : 1)).round()} kcal',
                ),
                InfoTile(
                  'Energi hele turen per pers.',
                  '${plan.totalKcalPerPerson.round()} kcal',
                ),
                InfoTile(
                  'Planlagt mat for hele gruppen',
                  '${(plan.totalKcalPerPerson * plan.people).round()} kcal',
                ),
              ],
            ],
          ),
          if (plan.dietaryPreferences.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final d in plan.dietaryPreferences)
                  Chip(
                    label: Text(d, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if ([
            for (var day = 1; day <= plan.days; day++)
              if (!plan.meals.any((meal) => meal.day == day)) day,
          ].isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Noen turdager mangler måltider etter endringer i turen. '
                'Legg til måltider eller velg en matmeny før avreise.',
                style: TextStyle(
                  color: NkColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _EnergyEstimateRow(trip: trip, plan: plan),
        ],
      ),
    );
  }

  void _settings(BuildContext context) {
    final water = TextEditingController(
      text: plan.waterLitersPerPersonDay.toStringAsFixed(1),
    );
    final diet = TextEditingController(
      text: plan.dietaryPreferences.join(', '),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matplan-innstillinger'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: water,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Liter vann per person per dag',
                helperText: 'Kun det du bærer – juster etter vanntilgang',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: diet,
              decoration: const InputDecoration(
                labelText: 'Kostholdspreferanser (kommaseparert)',
                helperText: 'F.eks. vegetar, glutenfri, laktosefri',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () async {
              plan.waterLitersPerPersonDay =
                  double.tryParse(water.text.replaceAll(',', '.')) ??
                  plan.waterLitersPerPersonDay;
              plan.dietaryPreferences = diet.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              // Sync food/water weights into packing list.
              await context.read<AppState>().updateMealPlan(trip);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
  }
}

/// Estimated daily energy need vs what the plan actually provides —
/// computed from stage distance/ascent, carried pack weight, body
/// weight (profile) and the coldest forecast temperature.
class _EnergyEstimateRow extends StatelessWidget {
  final Trip trip;
  final MealPlan plan;
  const _EnergyEstimateRow({required this.trip, required this.plan});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final bodyKg = state.profile.weightKg > 0 ? state.profile.weightKg : 75.0;
    // Coldest forecast hour inside the trip window across all
    // fetched snapshots — feeds the cold supplement.
    double? minTemp;
    for (final w in trip.weather.values) {
      final hours = trip.startDate != null
          ? w.hoursBetween(
              trip.startDate!,
              (trip.endDate ?? trip.startDate!).add(const Duration(days: 1)),
            )
          : w.hours;
      for (final h in hours) {
        final t = h.temperature;
        if (t != null && (minTemp == null || t < minTemp)) {
          minTemp = t;
        }
      }
    }
    final est = estimateDailyKcal(trip, bodyKg: bodyKg, minTempC: minTemp);
    final planned = plan.totalKcalPerPerson / (plan.days > 0 ? plan.days : 1);
    final deficit = planned > 0 && planned < est.kcalPerDay * 0.8;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: deficit
            ? NkColors.warningAmber.withValues(alpha: 0.1)
            : NkColors.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_outlined,
                size: 16,
                color: deficit ? NkColors.warningAmber : NkColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Estimert behov: ~${est.kcalPerDay.round()} kcal/dag',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Hvile ${est.baseKcal.round()} + aktivitet ${est.activityKcal.round()}'
            '${est.avgMet > 0 ? ' (MET ~${est.avgMet.toStringAsFixed(1)})' : ''}'
            '${est.coldKcal > 0 ? ' + kulde ${est.coldKcal.round()}' : ''}'
            ' · sekk ~${est.packKg.toStringAsFixed(1)} kg × ${est.bodyKg.toStringAsFixed(0)} kg kropp'
            '${est.temperatureKnown ? '' : ' · uten kuldetillegg (ingen prognose)'}',
            style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
          ),
          if (deficit) ...[
            const SizedBox(height: 4),
            Text(
              'Planen gir ${planned.round()} kcal/dag – under estimert behov. Vurder mer mat eller tyngre måltider.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: NkColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final Trip trip;
  final MealPlan plan;
  final int day;
  const _DayCard({required this.trip, required this.plan, required this.day});

  @override
  Widget build(BuildContext context) {
    final meals = plan.meals.where((m) => m.day == day).toList()
      ..sort((a, b) => a.type.index.compareTo(b.type.index));
    final dayWeight = meals.fold<double>(
      0,
      (s, m) => s + m.gramsPerPerson * plan.people,
    );
    final dayKcal = plan.kcalPerPersonDay(day);
    final stage = day <= trip.stages.length ? trip.stages[day - 1] : null;

    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dag $day${stage != null ? ' – ${fmtDate(stage.date)}' : ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${fmtWeight(dayWeight)}${dayKcal > 0 ? ' · ${dayKcal.round()} kcal/pers' : ''}',
                style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (meals.firstOrNull?.sourceMenuId case final menuId?
              when meals.every((m) => m.sourceMenuId == menuId))
            Text(
              'Meny: ${foodMenuById(menuId)?.name ?? menuId}',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
          for (final meal in meals)
            _MealRow(trip: trip, meal: meal, people: plan.people),
          TextButton.icon(
            onPressed: () => _addMeal(context, day),
            icon: const Icon(Icons.add, size: 16),
            label: const Text(
              'Legg til måltid',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _addMeal(BuildContext context, int day) {
    final plan = trip.mealPlan!;
    final name = TextEditingController();
    final grams = TextEditingController(text: '150');
    final kcal = TextEditingController();
    var type = MealType.snack;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Nytt måltid – dag $day'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<MealType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in MealType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setD(() => type = v!),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Beskrivelse'),
              ),
              TextField(
                controller: grams,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Gram per person (estimat)',
                ),
              ),
              TextField(
                controller: kcal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'kcal per 100 g (valgfritt)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () async {
                plan.meals.add(
                  PlannedMeal(
                    id: const Uuid().v4().substring(0, 8),
                    day: day,
                    userEdited: true,
                    type: type,
                    name: name.text.trim().isEmpty
                        ? type.label
                        : name.text.trim(),
                    gramsPerPerson: double.tryParse(grams.text) ?? 0,
                    kcalPer100g: double.tryParse(kcal.text) ?? 0,
                  ),
                );
                await context.read<AppState>().updateMealPlan(trip);
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

class _MealRow extends StatelessWidget {
  final Trip trip;
  final PlannedMeal meal;
  final int people;
  const _MealRow({
    required this.trip,
    required this.meal,
    required this.people,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (meal.type) {
      MealType.breakfast => Icons.free_breakfast_outlined,
      MealType.lunch => Icons.lunch_dining_outlined,
      MealType.dinner => Icons.dinner_dining_outlined,
      MealType.snack => Icons.cookie_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NkColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${meal.type.label}: ${meal.name}',
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  '${meal.gramsPerPerson.toStringAsFixed(0)} g/pers'
                  '${people > 1 ? ' ×$people = ${(meal.gramsPerPerson * people).toStringAsFixed(0)} g' : ''}'
                  '${meal.kcalPerPerson > 0 ? ' · ${meal.kcalPerPerson.round()} kcal/pers' : ''}',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: () => _edit(context),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.swap_horiz,
              size: 16,
              color: NkColors.primaryBlue,
            ),
            tooltip: 'Bytt ut',
            onPressed: () => _swap(context),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: NkColors.dangerRed,
            ),
            onPressed: () async {
              trip.mealPlan!.meals.removeWhere((m) => m.id == meal.id);
              await context.read<AppState>().updateMealPlan(trip);
            },
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    final name = TextEditingController(text: meal.name);
    final grams = TextEditingController(
      text: meal.gramsPerPerson.toStringAsFixed(0),
    );
    final kcal = TextEditingController(
      text: meal.kcalPer100g > 0 ? meal.kcalPer100g.toStringAsFixed(0) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger måltid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Beskrivelse'),
            ),
            TextField(
              controller: grams,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Gram per person'),
            ),
            TextField(
              controller: kcal,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'kcal per 100 g (valgfritt)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () async {
              meal.userEdited = true;
              meal.name = name.text.trim();
              meal.gramsPerPerson =
                  double.tryParse(grams.text) ?? meal.gramsPerPerson;
              meal.kcalPer100g = double.tryParse(kcal.text) ?? meal.kcalPer100g;
              await context.read<AppState>().updateMealPlan(trip);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
  }

  void _swap(BuildContext context) {
    // (name, realistic kcal per 100 g) — swapping must update the
    // energy density too, not just the label.
    final alternatives = switch (meal.type) {
      MealType.breakfast => [
        ('Grøtris med syltetøy og melk', 370),
        ('Frokostblanding med yoghurtpulver', 400),
        ('Brød med ost og skinke', 300),
      ],
      MealType.lunch => [
        ('Knekkebrød med makrell i tomat', 320),
        ('Tortilla med pålegg', 310),
        ('Suppe (pulver) med brød', 350),
      ],
      MealType.dinner => [
        ('Pasta med tørket tomatsaus', 380),
        ('Risgryte med kylling i pose', 420),
        ('Tørket fiskesuppe', 400),
      ],
      MealType.snack => [
        ('Energibarer', 440),
        ('Tørket frukt og nøtter', 480),
        ('Sjokolade og kjeks', 500),
      ],
    };
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bytt ut måltid'),
        children: [
          for (final (name, kcal) in alternatives)
            SimpleDialogOption(
              onPressed: () async {
                meal.userEdited = true;
                meal.name = name;
                meal.kcalPer100g = kcal.toDouble();
                await context.read<AppState>().updateMealPlan(trip);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(name),
            ),
        ],
      ),
    );
  }
}
