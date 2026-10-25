import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/recommendation.dart';
import '../models/trip.dart';
import '../services/trip_analysis.dart';
import '../state/app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'elevation_screen.dart';
import 'meals_screen.dart';
import 'hiking_screen.dart';
import 'recommendations_screen.dart';
import 'trips_screen.dart';
import 'weather_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip ?? state.nextTrip;
    final wide = context.isWide;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(hasTrip: trip != null)),
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 28 : 16,
                vertical: 8,
              ),
              sliver: SliverList.list(
                children: [
                  if (trip != null)
                    _UpcomingTripCard(trip: trip)
                  else
                    _NoTripCard(),
                  const SizedBox(height: 24),
                  if (trip != null) ...[
                    _AlertsSection(trip: trip),
                    const SizedBox(height: 24),
                    const SectionHeader(
                      'Forberedelser',
                      icon: Icons.fact_check_outlined,
                    ),
                    const SizedBox(height: 12),
                    _ReadinessGrid(trip: trip),
                    const SizedBox(height: 24),
                  ],
                  if (state.trips.length > 1) ...[
                    SectionHeader(
                      'Tidligere og lagrede turer',
                      icon: Icons.history,
                      trailing: TextButton(
                        onPressed: () => context.read<NavController>().goTo(1),
                        child: const Text('Se alle'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _RecentTrips(
                      trips: state.trips
                          .where((t) => t.id != trip?.id)
                          .take(4)
                          .toList(),
                    ),
                    const SizedBox(height: 32),
                  ] else
                    const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool hasTrip;
  const _Header({required this.hasTrip});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ScenicImage(
          url: NkImages.besseggenPano,
          height: 190,
          overlayOpacity: 0.45,
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 16,
          child: Row(
            children: [
              const Icon(Icons.explore, color: Colors.white, size: 30),
              const SizedBox(width: 10),
              const Text(
                'NorgesKompasset',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Anbefalinger for valgt tur',
                    onPressed: () {
                      final state = context.read<AppState>();
                      final trip = state.currentTrip ?? state.nextTrip;
                      if (trip != null) state.selectTrip(trip.id);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RecommendationsScreen(),
                        ),
                      );
                    },
                  ),
                  Consumer<AppState>(
                    builder: (ctx, s, child) {
                      final alerts =
                          (s.currentTrip ?? s.nextTrip)?.recommendations
                              .where(
                                (r) =>
                                    r.status == RecommendationStatus.active &&
                                    r.level != RecommendationLevel.info,
                              )
                              .length ??
                          0;
                      if (alerts == 0) return const SizedBox.shrink();
                      return Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: NkColors.dangerRed,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$alerts',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          bottom: 16,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasTrip ? 'Din valgte tur' : 'Klar for fjellet?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasTrip
                    ? 'Bytt tur fra Turer-fanen. Verktøyene følger valgt tur.'
                    : 'Planlegg, pakk riktig, og gå trygt.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoTripCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return NkCard(
      child: Column(
        children: [
          const Icon(
            Icons.add_location_alt_outlined,
            size: 48,
            color: NkColors.primaryBlue,
          ),
          const SizedBox(height: 12),
          Text(
            'Ingen tur planlagt ennå',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: NkColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Velg start- og endepunkt på kartet, sett datoer, og få høydeprofil, værvarsel og pakkeliste automatisk.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.read<NavController>().goTo(2),
            icon: const Icon(Icons.add),
            label: const Text('Planlegg ny tur'),
          ),
        ],
      ),
    );
  }
}

class _UpcomingTripCard extends StatelessWidget {
  final Trip trip;
  const _UpcomingTripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final route = trip.route;
    // A 0,0 km 'route' (start and goal on the same spot) does not
    // count as a planned route.
    final hasRoute =
        route?.hasRoute == true && (route?.distanceMeters ?? 0) > 0;
    final hasDates = trip.startDate != null;
    final packed =
        hasRoute &&
        trip.packingList.isNotEmpty &&
        trip.missingRequiredCount == 0;
    final active = trip.status == TripStatus.active;
    // One obvious next step: Rute → Datoer → Pakking → Klar.
    final (nextLabel, nextIcon) = active
        ? ('Fortsett turen', Icons.navigation)
        : !hasRoute
        ? ('Planlegg rute', Icons.map_outlined)
        : !hasDates
        ? ('Sett datoer', Icons.calendar_today_outlined)
        : !packed
        ? ('Pakk sekken', Icons.backpack_outlined)
        : ('Start tur', Icons.navigation);
    return NkCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.name.isEmpty ? 'Tur uten navn' : trip.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: NkColors.textPrimary,
                        ),
                      ),
                    ),
                    StatusPill(trip.status.label, NkColors.primaryBlue),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _IconText(
                      Icons.calendar_today_outlined,
                      '${fmtDate(trip.startDate)} – ${fmtDate(trip.endDate)}',
                    ),
                    _IconText(
                      Icons.schedule,
                      fmtCount(trip.hikingDays, 'dag', 'dager'),
                    ),
                    _IconText(Icons.bed_outlined, trip.accommodation.label),
                    if (route != null && route.hasRoute)
                      _IconText(
                        Icons.route_outlined,
                        fmtKm(route.distanceMeters),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _TripSteps(
                  steps: [
                    ('Rute', hasRoute),
                    ('Datoer', hasRoute && hasDates),
                    ('Pakking', packed && hasDates),
                    ('Klar', active || (packed && hasDates)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          context.read<AppState>().selectTrip(trip.id);
                          if (active || (packed && hasDates)) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HikingScreen(),
                              ),
                            );
                          } else {
                            context.read<NavController>().goTo(
                              hasRoute && hasDates ? 3 : 2,
                            );
                          }
                        },
                        icon: Icon(nextIcon, size: 18),
                        label: Text(nextLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        context.read<AppState>().selectTrip(trip.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ElevationScreen(),
                          ),
                        );
                      },
                      child: const Text('Analyse'),
                    ),
                  ],
                ),
                if (route != null && route.hasRoute) ...[
                  const SizedBox(height: 8),
                  _OfflineMapButton(trip: trip),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent "download map for offline use" action on the home trip
/// card — the map must be cached *before* leaving coverage.
/// Compact progress row for the planning steps, e.g. «Rute ✓ › Datoer».
class _TripSteps extends StatelessWidget {
  final List<(String, bool)> steps;
  const _TripSteps({required this.steps});

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s.$2).length;
    return Semantics(
      label: 'Steg $done av ${steps.length} fullført',
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, (label, ok)) in steps.indexed) ...[
            if (i > 0)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: NkColors.textSecondary,
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: ok ? NkColors.forestGreen : NkColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: ok ? FontWeight.w600 : FontWeight.w500,
                    color: NkColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OfflineMapButton extends StatelessWidget {
  final Trip trip;
  const _OfflineMapButton({required this.trip});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final done = state.tilesDone;
    final total = state.tilesTotal;
    final downloading = done != null && total != null;
    final coverage = state.offlineCoverage(trip);

    if (downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Laster ned kartfliser $done/$total…',
                  style: const TextStyle(
                    fontSize: 12,
                    color: NkColors.primaryBlue,
                  ),
                ),
              ),
              TextButton(
                onPressed: state.cancelMapDownload,
                child: const Text('Avbryt', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          NkProgress(total == 0 ? 0 : done / total),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: () => state.downloadMapTiles(trip),
      icon: const Icon(Icons.download_for_offline_outlined, size: 18),
      // No Expanded here — OutlinedButton.icon already wraps the
      // label in a Flexible internally, and nested flex widgets
      // on the same child throw a ParentDataWidget conflict.
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Last ned kartet (offline)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            '${coverage.cached}/${coverage.total} fliser lagret · test i flymodus',
            style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: NkColors.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconText(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: NkColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
        ),
      ],
    );
  }
}

class _ReadinessGrid extends StatelessWidget {
  final Trip trip;
  const _ReadinessGrid({required this.trip});

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.textScalerOf(context).scale(14) > 20
        ? 1
        : context.isWide
        ? 4
        : 2;
    return LayoutBuilder(
      builder: (_, constraints) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final card in [
            _PackingCard(trip: trip),
            _MealCard(trip: trip),
            _WeatherCard(trip: trip),
            _RouteCard(trip: trip),
          ])
            SizedBox(
              width: (constraints.maxWidth - 12 * (columns - 1)) / columns,
              child: card,
            ),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget content;
  final VoidCallback onTap;
  final double? progress;

  const _ReadinessCard({
    required this.icon,
    required this.title,
    required this.content,
    required this.onTap,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return NkCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: NkColors.primaryBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: NkColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: NkColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          content,
          if (progress != null) ...[
            const SizedBox(height: 6),
            NkProgress(progress!),
          ],
        ],
      ),
    );
  }
}

class _PackingCard extends StatelessWidget {
  final Trip trip;
  const _PackingCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final items = trip.packingList.where((i) => !i.worn).toList();
    final equipment = items
        .where((i) => !i.isConsumable)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    final totalGrams = items.fold(0.0, (s, i) => s + i.totalWeightGrams);
    final packedGrams = items
        .where((i) => i.packed)
        .fold(0.0, (s, i) => s + i.totalWeightGrams);
    final weightProgress = totalGrams > 0 ? packedGrams / totalGrams : 0.0;
    final missing = trip.missingRequiredCount;
    return _ReadinessCard(
      icon: Icons.checklist,
      title: 'Pakking',
      progress: items.isEmpty ? null : weightProgress,
      onTap: () {
        context.read<AppState>().selectTrip(trip.id);
        context.read<NavController>().goTo(3);
      },
      content: items.isEmpty
          ? Text(
              'Ikke generert ennå',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtWeight(packedGrams)} av ${fmtWeight(totalGrams)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: NkColors.forestGreen,
                  ),
                ),
                Text(
                  missing == 0
                      ? 'Alt nødvendig er pakket'
                      : '${fmtCount(missing, 'nødvendig ting', 'nødvendige ting')} mangler',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
                Text(
                  'Utstyr: ${fmtWeight(equipment)}',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
              ],
            ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final Trip trip;
  const _MealCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final plan = trip.mealPlan;
    return _ReadinessCard(
      icon: Icons.restaurant_outlined,
      title: 'Matplan',
      onTap: () {
        context.read<AppState>().selectTrip(trip.id);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MealsScreen()),
        );
      },
      content: plan == null
          ? Text(
              'Ingen matplan',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtCount(plan.days, 'dag', 'dager')} · ${plan.meals.length} måltider',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: NkColors.textPrimary,
                  ),
                ),
                Text(
                  'Matvekt: ${fmtWeight(plan.totalFoodWeightGrams)}',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
                Text(
                  'Vann: ${fmtWeight(plan.totalWaterWeightGrams)}',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
              ],
            ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final Trip trip;
  const _WeatherCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final snaps = trip.weather.values.toList();
    final start = trip.startDate;
    ConditionsSummary? c;
    if (snaps.isNotEmpty && start != null) {
      c = TripAnalysis.summarize(
        snaps,
        start,
        start.add(Duration(days: trip.hikingDays)),
      );
    }
    return _ReadinessCard(
      icon: Icons.cloud_outlined,
      title: 'Vær',
      onTap: () {
        context.read<AppState>().selectTrip(trip.id);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WeatherScreen()),
        );
      },
      content: c == null || !c.hasData
          ? Text(
              'Ingen prognose hentet',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtTemp(c.minTemp)} – ${fmtTemp(c.maxTemp)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: NkColors.primaryBlue,
                  ),
                ),
                if (c.rainExpected)
                  Text(
                    'Nedbør: ${c.totalPrecipMm.toStringAsFixed(1)} mm',
                    style: TextStyle(
                      fontSize: 11,
                      color: NkColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (c.strongWind)
                  Text(
                    'Vind til ${fmtWind(c.maxWind)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: NkColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  fmtAge(snaps.first.retrievedAt),
                  style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
                ),
              ],
            ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final Trip trip;
  const _RouteCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final route = trip.route;
    return _ReadinessCard(
      icon: Icons.route,
      title: 'Rute',
      onTap: () {
        context.read<AppState>().selectTrip(trip.id);
        context.read<NavController>().goTo(2);
      },
      content: route == null || !route.hasRoute
          ? Text(
              'Ikke planlagt',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtKm(route.distanceMeters),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: NkColors.textPrimary,
                  ),
                ),
                Text(
                  'Stigning: +${route.totalAscent.round()} m / -${route.totalDescent.round()} m',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
                Text(
                  route.sourceLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: NkColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );
  }
}

class _AlertsSection extends StatelessWidget {
  final Trip trip;
  const _AlertsSection({required this.trip});

  @override
  Widget build(BuildContext context) {
    final active = trip.recommendations
        .where((r) => r.status == RecommendationStatus.active)
        .toList();
    final unpacked = trip.packingList.where((i) => !i.worn && !i.packed).length;
    final coverage = context.watch<AppState>().offlineCoverage(trip);
    final tasks = <String>[
      if (trip.route == null || !trip.route!.hasRoute)
        'Planlegg ruten på kartet',
      if (trip.startDate == null) 'Sett datoer for turen',
      if (trip.packingList.isEmpty) 'Generer pakkeliste',
      // A generated-but-untouched list is not "ready" — the pack
      // still has to be physically packed.
      if (trip.packingList.isNotEmpty && unpacked > 0)
        'Pakk sekken – ${fmtCount(unpacked, 'gjenstand', 'gjenstander')} igjen',
      if (trip.mealPlan == null) 'Lag matplan',
      if (trip.weather.isEmpty && trip.route?.hasRoute == true)
        'Hent værprognose',
      if (coverage.total > 0 && coverage.cached < coverage.total)
        'Last ned manglende kartfliser for denne turen',
    ];

    if (active.isEmpty && tasks.isEmpty) {
      return NkCard(
        color: NkColors.forestGreen.withValues(alpha: 0.08),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: NkColors.forestGreen),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Alt ser klart ut – ingen åpne forberedelser.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: NkColors.forestGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          'Viktige endringer og oppgaver',
          icon: Icons.priority_high,
        ),
        const SizedBox(height: 10),
        for (final r in active.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NkCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    r.level == RecommendationLevel.serious
                        ? Icons.error_outline
                        : r.level == RecommendationLevel.caution
                        ? Icons.warning_amber_outlined
                        : Icons.info_outline,
                    color: r.level == RecommendationLevel.serious
                        ? NkColors.dangerRed
                        : r.level == RecommendationLevel.caution
                        ? NkColors.warningAmber
                        : NkColors.primaryBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          r.observation,
                          style: TextStyle(
                            fontSize: 12,
                            color: NkColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final t
            in tasks
                .where((t) => !active.take(3).any((r) => r.title == t))
                .take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.radio_button_unchecked,
                  size: 16,
                  color: NkColors.warningAmber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t,
                    style: TextStyle(fontSize: 13, color: NkColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        if (active.length > 3 || tasks.length > 3)
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecommendationsScreen()),
            ),
            child: const Text('Se alle anbefalinger'),
          ),
      ],
    );
  }
}

class _RecentTrips extends StatelessWidget {
  final List<Trip> trips;
  const _RecentTrips({required this.trips});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final t in trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NkCard(
              onTap: () {
                context.read<AppState>().selectTrip(t.id);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TripsScreen()),
                );
              },
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    t.status == TripStatus.completed
                        ? Icons.check_circle_outline
                        : Icons.hiking_outlined,
                    color: t.status == TripStatus.completed
                        ? NkColors.forestGreen
                        : NkColors.primaryBlue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name.isEmpty ? 'Tur uten navn' : t.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${t.status.label} · ${fmtDate(t.startDate)}${t.route?.hasRoute == true ? ' · ${fmtKm(t.route!.distanceMeters)}' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: NkColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(t.status.label, NkColors.primaryBlue),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
