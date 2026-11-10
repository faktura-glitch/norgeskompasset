import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/test_env.dart';
import '../core/theme.dart';
import '../models/catalog_trip.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';
import '../services/map_display_settings.dart';
import '../services/tile_cache.dart';
import '../state/app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';

class FindToursScreen extends StatefulWidget {
  const FindToursScreen({super.key});

  @override
  State<FindToursScreen> createState() => _FindToursScreenState();
}

class _FindToursScreenState extends State<FindToursScreen> {
  String _query = '';
  TripSeason? _season;
  String _region = '';
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted || context.read<AppState>().localOnly) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().loadCatalog(force: force);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kunne ikke hente delte turer. Prøv igjen.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCreatedTrip() {
    context.read<NavController>().goTo(2);
    Navigator.of(context).pop();
  }

  Future<void> _showPublished(CatalogTrip entry) async {
    if (_saving) return;
    final isAdmin = context.read<AppState>().isAdmin;
    DateTime? date;
    var days = entry.durationDays;
    var activity = entry.activity;
    var season = entry.seasons.firstOrNull ?? TripSeason.summer;
    var accommodation = entry.accommodation;
    var carry = activity == TripActivity.paddle
        ? CarryMode.canoe
        : CarryMode.backpack;
    var participants = 1;
    final selected =
        await showDialog<
          (
            DateTime,
            int,
            TripActivity,
            TripSeason,
            AccommodationType,
            CarryMode,
            int,
          )
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(entry.name),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.description),
                      Text(
                        '${entry.region} · ${fmtKm(entry.route.distanceMeters)}',
                      ),
                      Text(entry.route.sourceLabel),
                      const SizedBox(height: 8),
                      _RouteSketch(route: entry.route),
                      const SizedBox(height: 12),
                      const Text(
                        'Brukerpublisert rute, ikke kontrollert av NorgesKompasset. Kontroller trasé, forhold og varighet før avreise.',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Aktivitet:'),
                          const SizedBox(width: 12),
                          DropdownButton<TripActivity>(
                            value: activity,
                            onChanged: (v) => update(() {
                              activity = v ?? activity;
                              if (activity == TripActivity.paddle) {
                                carry = CarryMode.canoe;
                              } else if (carry == CarryMode.canoe) {
                                carry = CarryMode.backpack;
                              }
                            }),
                            items: [
                              for (final a in TripActivity.values)
                                DropdownMenuItem(
                                  value: a,
                                  child: Text(a.label),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Antall dager:'),
                          IconButton(
                            tooltip: 'Færre dager',
                            onPressed: days <= 1
                                ? null
                                : () => update(() => days--),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$days'),
                          IconButton(
                            tooltip: 'Flere dager',
                            onPressed: days >= 14
                                ? null
                                : () => update(() => days++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<TripSeason>(
                        initialValue: season,
                        decoration: const InputDecoration(
                          labelText: 'Sesong for pakkelisten',
                        ),
                        items: [
                          for (final s in TripSeason.values)
                            DropdownMenuItem(value: s, child: Text(s.label)),
                        ],
                        onChanged: (v) => update(() => season = v ?? season),
                      ),
                      DropdownButtonFormField<AccommodationType>(
                        initialValue: accommodation,
                        decoration: const InputDecoration(
                          labelText: 'Overnatting',
                        ),
                        items: [
                          for (final a in AccommodationType.values)
                            DropdownMenuItem(value: a, child: Text(a.label)),
                        ],
                        onChanged: (v) =>
                            update(() => accommodation = v ?? accommodation),
                      ),
                      DropdownButtonFormField<CarryMode>(
                        key: ValueKey('carry-${carry.name}'),
                        initialValue: carry,
                        decoration: const InputDecoration(labelText: 'Bæring'),
                        items: [
                          for (final mode in CarryMode.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Text(mode.label),
                            ),
                        ],
                        onChanged: (v) => update(() => carry = v ?? carry),
                      ),
                      Row(
                        children: [
                          const Text('Deltakere:'),
                          IconButton(
                            tooltip: 'Færre deltakere',
                            onPressed: participants <= 1
                                ? null
                                : () => update(() => participants--),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$participants'),
                          IconButton(
                            tooltip: 'Flere deltakere',
                            onPressed: participants >= 20
                                ? null
                                : () => update(() => participants++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const Text(
                        'Valgene brukes før pakkeliste og matplan opprettes. '
                        'Kontroller vær og forhold før avreise.',
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          date == null
                              ? 'Velg startdato'
                              : '${date!.day}.${date!.month}.${date!.year}',
                        ),
                        onPressed: () async {
                          final now = DateUtils.dateOnly(DateTime.now());
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date ?? now,
                            firstDate: now,
                            lastDate: DateTime(now.year + 3),
                          );
                          if (picked != null && context.mounted) {
                            update(() => date = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isAdmin)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Slett (admin)'),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _adminDelete(entry);
                    },
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: const Text('Rapporter'),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _reportEntry(entry);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  onPressed: date == null
                      ? null
                      : () => Navigator.pop(dialogContext, (
                          date!,
                          days,
                          activity,
                          season,
                          accommodation,
                          carry,
                          participants,
                        )),
                  child: const Text('Opprett eget utkast'),
                ),
              ],
            ),
          ),
        );
    if (selected == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppState>().startFromCatalog(
        entry,
        startDate: selected.$1,
        days: selected.$2,
        activity: selected.$3,
        season: selected.$4,
        accommodation: selected.$5,
        carry: selected.$6,
        participants: selected.$7,
      );
      if (mounted) _openCreatedTrip();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kunne ikke lagre utkastet. Prøv igjen.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Admins (config/admins in Firestore) may remove any shared tour.
  Future<void> _adminDelete(CatalogTrip entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett delt tur?'),
        content: Text(
          '«${entry.name}» fjernes for alle brukere. Dette kan ikke angres.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await context.read<AppState>().adminDeleteCatalogEntry(entry);
    if (!mounted) return;
    nkToast(
      context,
      done
          ? 'Turen er slettet for alle.'
          : 'Kunne ikke slette. Sjekk at din bruker-ID står i config/admins.',
    );
  }

  /// Admin review: keeps a reported tour (clears its reports).
  Future<void> _adminKeep(CatalogTrip entry) async {
    final done = await context.read<AppState>().adminKeepCatalogEntry(entry);
    if (!mounted) return;
    nkToast(
      context,
      done ? 'Turen beholdes og er synlig igjen.' : 'Kunne ikke oppdatere. Sjekk at din bruker-ID står i config/admins.',
    );
  }

  Future<void> _reportEntry(CatalogTrip entry) async {
    final ok = await context.read<AppState>().reportCatalogEntry(entry);
    if (!mounted) return;
    nkToast(
      context,
      ok
          ? 'Takk – turen er rapportert. Den skjules etter '
                '${CatalogTrip.reportHideThreshold} rapporter.'
          : 'Kunne ikke sende rapporten. Logg inn og prøv igjen.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = _query.trim().toLowerCase();
    final regions = {
      for (final entry in state.catalog)
        if (entry.region.trim().isNotEmpty) entry.region.trim(),
    }.toList()..sort();
    final entries = state.catalog.where((entry) {
      if (!entry.matches(_season, null)) return false;
      if (_region.isNotEmpty &&
          entry.region.trim().toLowerCase() != _region.toLowerCase()) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${entry.name} ${entry.region} ${entry.description}'
          .toLowerCase()
          .contains(query);
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Turer delt av brukere')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Søk etter tur eller område',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Alle sesonger'),
                selected: _season == null,
                onSelected: (_) => setState(() => _season = null),
              ),
              for (final season in TripSeason.values)
                FilterChip(
                  label: Text(season.label),
                  selected: _season == season,
                  onSelected: (on) =>
                      setState(() => _season = on ? season : null),
                ),
              if (regions.isNotEmpty)
                DropdownButton<String>(
                  value: regions.contains(_region) ? _region : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Alle områder')),
                    for (final region in regions)
                      DropdownMenuItem(value: region, child: Text(region)),
                  ],
                  onChanged: (value) => setState(() => _region = value ?? ''),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.localOnly)
            const Text(
              'Logg inn fra Mer for å se turer som andre brukere har delt.',
            )
          else ...[
            TextButton.icon(
              onPressed: _loading || _saving ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Oppdater delte turer'),
            ),
            if (_loading || _saving) const LinearProgressIndicator(),
            if (state.pendingReview.isNotEmpty)
              Card(
                color: NkColors.warningAmber.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fmtCount(state.pendingReview.length, 'rapportert tur', 'rapporterte turer')} venter på vurdering',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'Skjult for vanlige brukere til du bestemmer deg. '
                        'Trykk på turen for å se ruten.',
                        style: TextStyle(fontSize: 12),
                      ),
                      for (final entry in state.pendingReview) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${entry.name} · ${entry.reportedBy.length} rapporter',
                              style: const TextStyle(fontSize: 13),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _adminKeep(entry),
                              child: const Text('Behold'),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _adminDelete(entry),
                              child: const Text('Slett'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (!_loading && entries.isEmpty)
              const Text(
                'Ingen delte turer å vise. Prøv et annet søk, eller publiser en egen tur fra Turer.',
              ),
            for (final entry in entries)
              Card(
                child: ListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                    '${entry.difficulty.gradeLabel} · ${entry.region} · '
                    '${fmtKm(entry.route.distanceMeters)}\n'
                    '${entry.reportedBy.length >= CatalogTrip.reportHideThreshold ? 'Skjult for brukere – ${entry.reportedBy.length} rapporter' : 'Brukerpublisert · ikke kontrollert'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : () => _showPublished(entry),
                ),
              ),
          ],
          if (_error != null) Text(_error!),
        ],
      ),
    );
  }
}

/// Small non-interactive route sketch in the import dialog.
class _RouteSketch extends StatelessWidget {
  final HikingRoute route;

  const _RouteSketch({required this.route});

  @override
  Widget build(BuildContext context) {
    // Widget tests must not hit tile servers — show a placeholder
    // instead of a live map when running under `flutter test`.
    if (isFlutterTest()) {
      return Container(
        height: 180,
        width: double.infinity,
        color: Colors.grey.shade300,
        alignment: Alignment.center,
        child: const Icon(Icons.map_outlined),
      );
    }
    return SizedBox(
      height: 180,
      child: FlutterMap(
        key: ValueKey(route),
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(
            coordinates: route.latLngs,
            padding: const EdgeInsets.all(24),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: MapDisplaySettings.osm,
            tileProvider: PersistentTileProvider(),
            userAgentPackageName: 'ai.norgeskompasset.app',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.latLngs,
                color: Colors.deepOrange,
                strokeWidth: 4,
              ),
            ],
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
    );
  }
}
