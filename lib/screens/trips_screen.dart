import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/recommendation.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'hiking_screen.dart';
import 'review_screen.dart';
import 'safety_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  int _filter = 0;
  bool _joining = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trips = state.trips
        .where(
          (trip) =>
              trip.name.toLowerCase().contains(_query.toLowerCase()) &&
              switch (_filter) {
                1 =>
                  trip.status == TripStatus.draft ||
                      trip.status == TripStatus.planned,
                2 => trip.status == TripStatus.active,
                3 => trip.status == TripStatus.completed,
                _ => true,
              },
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turer'),
        actions: [
          IconButton(
            tooltip: 'Turforslag',
            color: Colors.white,
            icon: const Icon(Icons.travel_explore_outlined, size: 20),
            onPressed: () => context.read<NavController>().openMapExplore(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: NkColors.primaryBlue,
                backgroundColor: Colors.white,
              ),
              icon: const Icon(Icons.group_add_outlined, size: 20),
              label: const Text('Bli med på tur'),
              onPressed: () => _joinSharedTrip(context),
            ),
          ),
        ],
      ),
      body: state.trips.isEmpty
          ? EmptyState(
              icon: Icons.hiking_outlined,
              title: 'Ingen turer ennå',
              message:
                  'Opprett din første tur og planlegg ruten direkte på kartet — '
                  'eller bli med på en tur som er delt med deg.',
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => _createTrip(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Opprett tur'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.read<NavController>().openMapExplore(),
                    icon: const Icon(Icons.travel_explore_outlined, size: 18),
                    label: const Text('Se turforslag'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _joinSharedTrip(context),
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: const Text('Bli med på delt tur'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.read<NavController>().openMapExplore(),
                      icon: const Icon(Icons.hiking),
                      label: const Text('Finn turforslag og turer fra andre'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Søk i turene dine',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (i, label) in [
                      'Alle',
                      'Kommende',
                      'Pågående',
                      'Fullførte',
                    ].indexed)
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == i,
                        onSelected: (_) => setState(() => _filter = i),
                      ),
                  ],
                ),
                if (_joining) const LinearProgressIndicator(),
                Expanded(
                  child: trips.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Ingen turer matcher søket eller filteret.',
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _query = '';
                                  _filter = 0;
                                  _searchCtrl.clear();
                                }),
                                child: const Text('Nullstill søk og filter'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            context.isWide ? 28 : 16,
                            16,
                            16,
                            100,
                          ),
                          itemCount: trips.length,
                          itemBuilder: (_, i) => _TripTile(trip: trips[i]),
                        ),
                ),
              ],
            ),
      floatingActionButton: state.trips.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab-trips',
              onPressed: () => _createTrip(context),
              icon: const Icon(Icons.add),
              label: const Text('Ny tur'),
              backgroundColor: NkColors.forestGreen,
              foregroundColor: Colors.white,
            ),
    );
  }

  Future<void> _createTrip(BuildContext context) async {
    final state = context.read<AppState>();
    final name = await _askName(context);
    if (name == null) return;
    await state.createTrip(name: name);
    if (context.mounted) context.read<NavController>().goTo(2);
  }

  /// Enter the 6-letter code from a shared trip → fetches the
  /// snapshot and imports it as a local copy.
  Future<void> _joinSharedTrip(BuildContext context) async {
    final state = context.read<AppState>();
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bli med på delt tur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Skriv inn turkoden du har fått fra den som planlegger turen. '
              'Du får rute, datoer og planen – og lager din egen pakkeliste '
              'og matplan ut fra din profil og ditt utstyr. Dette er en egen kopi, ikke en løpende felles plan.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Turkode',
                hintText: 'F.eks. X7K2PM',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Hent tur'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    setState(() => _joining = true);
    final trip = await state.joinSharedTrip(code);
    if (!context.mounted) return;
    setState(() => _joining = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          trip != null
              ? '«${trip.name}» er lagt til i turene dine'
              : 'Fant ingen delt tur med koden «$code» — sjekk at den er riktig og at du er på nett.',
        ),
      ),
    );
  }

  Future<String?> _askName(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny tur'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Turnavn',
            hintText: 'F.eks. Besseggen',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Opprett'),
          ),
        ],
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  final Trip trip;
  const _TripTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final route = trip.route;
    final conflicted = state.cloudConflicts.contains(trip.id);
    final activeRecs = trip.recommendations
        .where(
          (r) =>
              r.status == RecommendationStatus.active &&
              r.level != RecommendationLevel.info,
        )
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NkCard(
        onTap: () {
          state.selectTrip(trip.id);
          context.read<NavController>().goTo(2);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip.name.isEmpty ? 'Tur uten navn' : trip.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (state.currentTrip?.id == trip.id)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: StatusPill('Valgt tur', NkColors.forestGreen),
                  ),
                StatusPill(
                  trip.status.label,
                  trip.status == TripStatus.completed
                      ? NkColors.forestGreen
                      : NkColors.primaryBlue,
                ),
              ],
            ),
            if (conflicted) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => state.clearCloudConflict(trip.id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_sync_outlined,
                      size: 14,
                      color: NkColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Oppdatert fra en annen enhet – trykk for å skjule',
                      style: TextStyle(fontSize: 11, color: NkColors.warning),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                metaChip(
                  Icons.calendar_today_outlined,
                  '${fmtDate(trip.startDate)} – ${fmtDate(trip.endDate)}',
                ),
                if (route?.hasRoute == true)
                  metaChip(Icons.route_outlined, fmtKm(route!.distanceMeters)),
                metaChip(switch (trip.activity) {
                  TripActivity.ski => Icons.downhill_skiing,
                  TripActivity.bike => Icons.directions_bike_outlined,
                  TripActivity.paddle => Icons.kayaking_outlined,
                  _ => Icons.hiking_outlined,
                }, trip.activity.label),
                metaChip(Icons.bed_outlined, trip.accommodation.label),
                if (trip.stages.isNotEmpty)
                  metaChip(
                    Icons.flag_outlined,
                    '${trip.stages.length} etapper',
                  ),
                if (activeRecs > 0)
                  metaChip(
                    Icons.warning_amber_outlined,
                    '$activeRecs varsler',
                    color: NkColors.warning,
                  ),
                if (trip.shareCode != null)
                  metaChip(Icons.group_outlined, 'Delt: ${trip.shareCode}'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Pakket (vekt): ${(trip.packingCompletion * 100).round()} %',
              style: TextStyle(color: NkColors.textSecondary),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (trip.status != TripStatus.completed)
                  FilledButton.icon(
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Turmodus'),
                    onPressed: () {
                      state.selectTrip(trip.id);
                      if (trip.status == TripStatus.planned) {
                        state.setStatus(trip, TripStatus.active);
                      }
                      if (trip.route?.hasRoute == true &&
                          trip.route?.supportsDeviationAlerts != true) {
                        nkToast(
                          context,
                          'Ruten har ikke et fullstendig beregnet stispor – '
                          'avviksvarsling er avslått i turmodus.',
                        );
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HikingScreen()),
                      );
                    },
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Flere valg for turen',
                  onSelected: (value) async {
                    switch (value) {
                      case 'share':
                        await _shareTrip(context);
                      case 'safety':
                        state.selectTrip(trip.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SafetyScreen(),
                          ),
                        );
                      case 'copy':
                        await state.duplicateTrip(trip);
                        if (context.mounted) nkToast(context, 'Tur kopiert');
                      case 'publish':
                        await _publishCatalog(context);
                      case 'review':
                        state.selectTrip(trip.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReviewScreen(),
                          ),
                        );
                      case 'delete':
                        await _confirmDelete(context);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Del med turkode'),
                    ),
                    const PopupMenuItem(
                      value: 'safety',
                      child: Text('Turkort og sikkerhet'),
                    ),
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Dupliser tur'),
                    ),
                    if (trip.route?.hasRoute == true)
                      const PopupMenuItem(
                        value: 'publish',
                        child: Text('Publiser i turkatalogen'),
                      ),
                    const PopupMenuItem(
                      value: 'review',
                      child: Text('Evaluer turen'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Slett tur'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz),
                        SizedBox(width: 6),
                        Text('Flere valg'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Publishes a snapshot under a share code and shows the code in a
  /// dialog (copyable). Sharing again republishes the latest version.
  Future<void> _shareTrip(BuildContext context) async {
    final state = context.read<AppState>();
    final code = await state.shareTrip(trip);
    if (!context.mounted) return;
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kunne ikke dele turen — sjekk at du er innlogget og på nett.',
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tur delt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gi denne koden til de andre på turen — de henter turen '
              'inn via «Bli med på delt tur» på Turer-siden.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Deling på nytt oppdaterer kopiene.',
              style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Kopier kode'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Publishes the trip's route to the shared catalog so others can
  /// discover it in the map's explore mode.
  Future<void> _publishCatalog(BuildContext context) async {
    final state = context.read<AppState>();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publiser i turkatalogen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ruten blir synlig for alle innloggede brukere under '
              '«Finn tur» under Turer. Pakkeliste, spor og evaluering deles ikke.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Kort beskrivelse (valgfri)',
                hintText: 'F.eks. klassisk topptur med utsikt over…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publiser'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await state.publishTripToCatalog(
      trip,
      description: descCtrl.text.trim(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '«${trip.name.isEmpty ? 'Turen' : trip.name}» er publisert i katalogen'
              : 'Kunne ikke publisere — sjekk at du er innlogget og på nett.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett tur?'),
        content: Text(
          '«${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» og all tilknyttet data slettes permanent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NkColors.dangerRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final state = context.read<AppState>();
      // Resolve the messenger before the async delete — the tile is
      // unmounted once the trip leaves the list, so a context read
      // afterwards could be dead.
      final messenger = ScaffoldMessenger.of(context);
      final index = state.trips.indexOf(trip);
      await state.deleteTrip(trip.id);
      // Keep the trip object alive long enough to undo — the
      // repository delete is reverted by restoreTrip → saveTrip.
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '«${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» er slettet',
          ),
          action: SnackBarAction(
            label: 'Angre',
            onPressed: () =>
                state.restoreTrip(trip, index: index < 0 ? 0 : index),
          ),
          persist: false,
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }
}
