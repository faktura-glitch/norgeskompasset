import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/geo.dart';
import '../core/test_env.dart';
import '../core/format.dart';
import '../models/local_tour.dart';
import '../models/route_models.dart';
import '../models/trip.dart';
import '../services/local_tour_catalog.dart';
import '../services/map_display_settings.dart';
import '../services/tile_cache.dart';
import '../state/app_state.dart';

class LocalTourSuggestions extends StatefulWidget {
  final String query;
  final bool simpleOnly;
  final LatLng? userLocation;
  final bool nearest;
  final VoidCallback onRequestLocation;
  final ValueChanged<HikingRoute?>? onPreview;
  final ValueChanged<Trip> onImported;

  const LocalTourSuggestions({
    super.key,
    required this.query,
    this.simpleOnly = true,
    this.userLocation,
    this.nearest = false,
    required this.onRequestLocation,
    this.onPreview,
    required this.onImported,
  });

  @override
  State<LocalTourSuggestions> createState() => _LocalTourSuggestionsState();
}

class _LocalTourSuggestionsState extends State<LocalTourSuggestions> {
  String? _region;
  int _duration = 0;

  @override
  Widget build(BuildContext context) {
    final available = localTours.where(
      (tour) =>
          !widget.simpleOnly ||
          (tour.region == 'Nordmarka' && tour.durationDays == 1),
    );
    final tours = available
        .where(
          (tour) =>
              tour.matchesQuery(widget.query) &&
              (_region == null || tour.region == _region) &&
              (_duration == 0 ||
                  (_duration == 1
                      ? tour.durationDays == 1
                      : _duration == 2
                      ? tour.durationDays >= 2 && tour.durationDays <= 3
                      : tour.durationDays >= 4)),
        )
        .toList();
    final location = widget.userLocation;
    if (widget.nearest && location != null) {
      tours.sort(
        (a, b) => metersBetween(
          location,
          a.previewRoute().start!,
        ).compareTo(metersBetween(location, b.previewRoute().start!)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enkle turforslag i Nordmarka',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Text(
          'Tre ideer til dagsturer. Kartlinjene er punktskisser, ikke '
          'kontrollerte stispor. Kontroller trasé og forhold før avreise.',
        ),
        if (!widget.simpleOnly)
          Wrap(
            spacing: 6,
            children: [
              for (final region in available.map((tour) => tour.region).toSet())
                FilterChip(
                  label: Text(region),
                  selected: _region == region,
                  onSelected: (selected) =>
                      setState(() => _region = selected ? region : null),
                ),
            ],
          ),
        if (!widget.simpleOnly)
          Wrap(
            spacing: 6,
            children: [
              for (final (index, label) in [
                'Dagstur',
                'Helgetur',
                'Flerdagerstur',
              ].indexed)
                FilterChip(
                  label: Text(label),
                  selected: _duration == index + 1,
                  onSelected: (selected) =>
                      setState(() => _duration = selected ? index + 1 : 0),
                ),
              ActionChip(
                avatar: const Icon(Icons.my_location, size: 16),
                label: const Text('Nærmest meg'),
                onPressed: widget.onRequestLocation,
              ),
            ],
          ),
        if (tours.isEmpty)
          const Text('Ingen lokale turmaler matcher søket eller filtrene.'),
        for (final tour in tours)
          Card(
            child: ListTile(
              leading: Icon(
                tour.activity == TripActivity.paddle
                    ? Icons.kayaking
                    : tour.activity == TripActivity.ski
                    ? Icons.downhill_skiing
                    : Icons.hiking,
              ),
              title: Text(tour.name),
              subtitle: Text(
                '${tour.region} · ${tour.municipality}\n'
                '${tour.activity.label} · ${tour.carry.label} · ${fmtCount(tour.durationDays, 'dag', 'dager')}, planforslag\n'
                'Oppgitt: ${tour.reportedDistanceKm.toStringAsFixed(0)} km · ikke kontrollert'
                '${widget.nearest && location != null ? '\n${(metersBetween(location, tour.previewRoute().start!) / 1000).toStringAsFixed(1)} km i luftlinje til oppgitt start' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                widget.onPreview?.call(tour.previewRoute());
                showDialog<void>(
                  context: context,
                  builder: (_) => _LocalTourDialog(
                    tour: tour,
                    onImported: widget.onImported,
                  ),
                );
              },
            ),
          ),
        if (widget.onPreview != null)
          TextButton(
            onPressed: () => widget.onPreview?.call(null),
            child: const Text('Skjul turmalens kartskisse'),
          ),
      ],
    );
  }
}

class _LocalTourDialog extends StatefulWidget {
  final LocalTour tour;
  final ValueChanged<Trip> onImported;
  const _LocalTourDialog({required this.tour, required this.onImported});

  @override
  State<_LocalTourDialog> createState() => _LocalTourDialogState();
}

class _LocalTourDialogState extends State<_LocalTourDialog> {
  DateTime? _date;
  late int _days = widget.tour.durationDays;
  late TripSeason _season = widget.tour.season;
  int _participants = 1;
  late AccommodationType _accommodation = widget.tour.accommodation;
  bool _acknowledged = false;
  bool _saving = false;
  String? _error;

  Future<void> _import() async {
    if (_saving || !_acknowledged || _date == null) return;
    final state = context.read<AppState>();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final trip = await state.startFromLocalTour(
        widget.tour,
        startDate: _date!,
        days: _days,
        participants: _participants,
        accommodation: _accommodation,
        acknowledgedUnverified: _acknowledged,
        season: _season,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onImported(trip);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Kunne ikke opprette turen. Ingen ny tur er lagt til i listen. Prøv igjen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tour = widget.tour;
    return AlertDialog(
      title: Text(tour.name),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tour.provenance,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(tour.description),
              const SizedBox(height: 8),
              if (isFlutterTest())
                Container(
                  height: 180,
                  width: double.infinity,
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.map_outlined),
                )
              else
                SizedBox(
                  height: 180,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.coordinates(
                        coordinates: tour.previewRoute().latLngs,
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
                            points: tour.previewRoute().latLngs,
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
                ),
              const Text(
                'Skissen binder punktene med rette linjer – den er ikke et stispor.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                'Oppgitt lengde: ${tour.reportedDistanceKm} km. '
                'Oppgitt stigning: ${tour.reportedElevationGainMeters == null ? 'ukjent' : '${tour.reportedElevationGainMeters!.round()} m'}. '
                'Tallene er ikke målte rutestatistikker.',
              ),
              Text(
                'Oppgitte måneder: ${tour.months.join(', ')}. '
                'Aktivitet: ${tour.activity.label}. Bæring: ${tour.carry.label}.',
              ),
              const SizedBox(height: 8),
              Text(
                tour.warning,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(LocalTour.limitations),
              const SizedBox(height: 8),
              for (final stop in tour.stops) Text('• ${stop.name}'),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _date ?? now,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 3, 12, 31),
                        );
                        if (date != null && mounted) {
                          setState(() => _date = date);
                        }
                      },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  _date == null
                      ? 'Velg startdato'
                      : 'Start: ${_date!.day}.${_date!.month}.${_date!.year}',
                ),
              ),
              if (_date != null && !tour.months.contains(_date!.month))
                const Text(
                  'Valgt dato er utenfor malens oppgitte måneder. '
                  'Sesongvalget erstatter ikke kontroll av snø, is eller lokale forhold.',
                ),
              DropdownButtonFormField<TripSeason>(
                initialValue: _season,
                decoration: const InputDecoration(
                  labelText:
                      'Sesong for pakkelisten – kontroller mot forholdene',
                ),
                items: [
                  for (final season in TripSeason.values)
                    DropdownMenuItem(value: season, child: Text(season.label)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _season = value!),
              ),
              DropdownButtonFormField<int>(
                initialValue: _days,
                decoration: const InputDecoration(
                  labelText: 'Planlagt antall dager',
                ),
                items: [
                  for (var i = 1; i <= 14; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _days = value!),
              ),
              DropdownButtonFormField<int>(
                initialValue: _participants,
                decoration: const InputDecoration(labelText: 'Deltakere'),
                items: [
                  for (var i = 1; i <= 50; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _participants = value!),
              ),
              DropdownButtonFormField<AccommodationType>(
                initialValue: _accommodation,
                decoration: const InputDecoration(labelText: 'Overnatting'),
                items: [
                  for (final type in AccommodationType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _accommodation = value!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acknowledged,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _acknowledged = value ?? false),
                title: const Text(
                  'Jeg forstår at punktene er ukontrollerte, '
                  'og at kartskissen og pakkelisten ikke bekrefter at turen er trygg.',
                ),
              ),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: _saving || !_acknowledged || _date == null
              ? null
              : _import,
          child: Text(
            _saving ? 'Oppretter…' : 'Opprett utkast og foreløpig pakkeliste',
          ),
        ),
      ],
    );
  }
}
