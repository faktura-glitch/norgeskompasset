import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/recommendation.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/app_shell.dart';
import 'weather_screen.dart';
import 'elevation_screen.dart';

class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    return Scaffold(
      appBar: AppBar(
        title: tripScreenTitle('Smarte anbefalinger', trip),
        actions: [
          if (trip != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Hent fersk vær og beregn på nytt',
              onPressed: state.busy
                  ? null
                  : () async {
                      // Recommendations are only as good as the data
                      // behind them — refresh weather before re-running.
                      await context.read<AppState>().fetchWeather(trip);
                      if (context.mounted) {
                        await context.read<AppState>().reanalyze(trip);
                      }
                    },
            ),
        ],
      ),
      body: trip == null
          ? const EmptyState(
              icon: Icons.lightbulb_outline,
              title: 'Ingen tur valgt',
              message:
                  'Anbefalinger kobles til en konkret tur. Velg en tur først.',
            )
          : _Body(trip: trip, wide: wide),
    );
  }
}

class _Body extends StatelessWidget {
  final Trip trip;
  final bool wide;
  const _Body({required this.trip, required this.wide});

  @override
  Widget build(BuildContext context) {
    final active =
        trip.recommendations
            .where((r) => r.status == RecommendationStatus.active)
            .toList()
          ..sort((a, b) => b.level.index.compareTo(a.level.index));
    final dismissed = trip.recommendations
        .where((r) => r.status != RecommendationStatus.active)
        .toList();

    if (active.isEmpty && dismissed.isEmpty) {
      return const EmptyState(
        icon: Icons.info_outline,
        title: 'Ingen råd å vise ennå',
        message: 'Anbefalinger genereres fra rute, etapper, vær og pakkeliste. Planlegg en tur og hent værdata for å se dem her.',
      );
    }

    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        ScreenBanner(
          url: NkImages.besseggenPano,
          title: 'Smarte anbefalinger',
          subtitle:
              'for «${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» — basert på rute, vær og pakkeliste',
        ),
        const SizedBox(height: 12),
        if (active.isNotEmpty)
          NkCard(
            padding: const EdgeInsets.all(12),
            color: NkColors.primaryBlue.withValues(alpha: 0.06),
            child: Text(
              'Anbefalingene er veiledende og basert på tilgjengelige data. De erstatter ikke eget skjønn eller lokalkunnskap – fravær av varsel betyr ikke at forholdene er trygge.',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
          ),
        const SizedBox(height: 12),
        for (final level in RecommendationLevel.values.reversed) ...[
          if (active.any((r) => r.level == level)) ...[
            SectionHeader(
              level.label,
              icon: level == RecommendationLevel.serious
                  ? Icons.error_outline
                  : level == RecommendationLevel.caution
                  ? Icons.warning_amber_outlined
                  : Icons.info_outline,
            ),
            const SizedBox(height: 8),
            for (final r in active.where((r) => r.level == level))
              _RecCard(rec: r, trip: trip),
            const SizedBox(height: 8),
          ],
        ],
        if (dismissed.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Håndterte og skjulte (${dismissed.length})',
              style: TextStyle(fontSize: 13, color: NkColors.textSecondary),
            ),
            children: [
              for (final r in dismissed)
                ListTile(
                  dense: true,
                  title: Text(
                    r.title,
                    style: const TextStyle(
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      r.status = RecommendationStatus.active;
                      await context.read<AppState>().saveTrip(trip);
                    },
                    child: const Text(
                      'Gjenopprett',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RecCard extends StatelessWidget {
  final Recommendation rec;
  final Trip trip;
  const _RecCard({required this.rec, required this.trip});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (rec.level) {
      RecommendationLevel.serious => (NkColors.dangerRed, Icons.error_outline),
      RecommendationLevel.caution => (
        NkColors.warningAmber,
        Icons.warning_amber_outlined,
      ),
      RecommendationLevel.info => (NkColors.primaryBlue, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rec.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (rec.stageNumber != null)
                  StatusPill('Etappe ${rec.stageNumber}', color),
              ],
            ),
            const SizedBox(height: 8),
            _row('Observert', rec.observation),
            _row('Hvorfor', rec.why),
            _row('Tiltak', rec.action, bold: true),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.checklist),
                  label: const Text('Pakkeliste'),
                  onPressed: () {
                    context.read<NavController>().goTo(3);
                    Navigator.pop(context);
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Vær'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WeatherScreen()),
                  ),
                ),
                if (rec.stageNumber != null)
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ElevationScreen(),
                      ),
                    ),
                    child: const Text('Se etapper'),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rec.sourceNote ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      color: NkColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    rec.status = RecommendationStatus.resolved;
                    await context.read<AppState>().saveTrip(trip);
                  },
                  child: const Text('Håndtert'),
                ),
                TextButton(
                  onPressed: () async {
                    rec.status = RecommendationStatus.dismissed;
                    await context.read<AppState>().saveTrip(trip);
                  },
                  child: const Text('Skjul', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: bold ? NkColors.forestGreen : NkColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
