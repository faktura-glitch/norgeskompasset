import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _distance = TextEditingController();
  final _duration = TextEditingController();
  final _ascent = TextEditingController();
  final _weather = TextEditingController();
  final _difficult = TextEditingController();
  final _notes = TextEditingController();
  // Equipment lists are picked from the trip's packing list so the
  // names match what the packing engine learns from.
  final _workedWell = <String>[];
  final _unnecessary = <String>[];
  final _missing = <String>[];
  int _rating = 3;
  bool _loaded = false;
  bool _prefilledFromTrack = false;

  /// The trip being reviewed — user-selectable, defaults to the
  /// active trip so earlier trips can be evaluated too.
  Trip? _trip;

  @override
  void dispose() {
    for (final c in [
      _distance,
      _duration,
      _ascent,
      _weather,
      _difficult,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Trip trip) {
    if (_loaded) return;
    _loaded = true;
    final r = trip.review;
    if (r != null) {
      _distance.text = r.actualDistanceKm?.toString() ?? '';
      _duration.text = r.actualDurationHours?.toString() ?? '';
      _ascent.text = r.actualAscent?.toString() ?? '';
      _weather.text = r.weatherExperienced;
      _workedWell.addAll(r.workedWell);
      _unnecessary.addAll(r.unnecessary);
      _missing.addAll(r.missing);
      _difficult.text = r.difficultSections;
      _notes.text = r.notes;
      _rating = r.rating;
    } else if (trip.trackLog.length >= 2) {
      // Auto-fill from the recorded GPS track — the user can still
      // adjust everything before saving.
      final log = trip.trackLog;
      var meters = 0.0, ascent = 0.0;
      for (var i = 1; i < log.length; i++) {
        meters += metersBetween(
          LatLng(log[i - 1].lat, log[i - 1].lon),
          LatLng(log[i].lat, log[i].lon),
        );
        final prev = log[i - 1].elevation, cur = log[i].elevation;
        if (prev != null && cur != null && cur > prev) {
          ascent += cur - prev;
        }
      }
      final hours = log.last.time.difference(log.first.time).inMinutes / 60;
      _distance.text = (meters / 1000).toStringAsFixed(1);
      _duration.text = hours.toStringAsFixed(1);
      if (ascent > 0) _ascent.text = ascent.round().toString();
      _prefilledFromTrack = true;
    } else if (trip.route?.hasRoute == true) {
      _distance.text = (trip.route!.distanceMeters / 1000).toStringAsFixed(1);
    }
  }

  /// Switches to another trip — clears the form and reloads from
  /// that trip's review/track/route data.
  void _selectTrip(Trip trip) {
    setState(() {
      _trip = trip;
      _loaded = false;
      _prefilledFromTrack = false;
      _rating = 3;
      for (final c in [
        _distance,
        _duration,
        _ascent,
        _weather,
        _difficult,
        _notes,
      ]) {
        c.clear();
      }
      _workedWell.clear();
      _unnecessary.clear();
      _missing.clear();
    });
    _load(trip);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _trip ??= state.currentTrip;
    final trip = _trip;
    final wide = context.isWide;

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: tripScreenTitle('Turevaluering', trip)),
        body: const EmptyState(
          icon: Icons.rate_review_outlined,
          title: 'Ingen tur valgt',
          message: 'Velg en tur for å registrere evaluering.',
        ),
      );
    }
    _load(trip);
    // Most recent first; every saved trip can be evaluated.
    final allTrips = List.of(state.trips)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      appBar: AppBar(title: tripScreenTitle('Turevaluering', trip)),
      body: ListView(
        padding: EdgeInsets.all(wide ? 28 : 16),
        children: [
          ScreenBanner(
            url: NkImages.besseggenRidge,
            title: 'Hva lærte du av turen?',
            subtitle:
                'for «${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» — erfaringer gjør neste plan bedre',
          ),
          const SizedBox(height: 14),
          if (allTrips.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: NkCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: DropdownButtonFormField<Trip>(
                  initialValue: trip,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tur som evalueres',
                    border: InputBorder.none,
                  ),
                  items: [
                    for (final t in allTrips)
                      DropdownMenuItem(
                        value: t,
                        child: Text(
                          '${t.name.isEmpty ? 'Tur uten navn' : t.name}'
                          ' · ${t.status.label}'
                          '${t.startDate != null ? ' · ${fmtDate(t.startDate)}' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: (t) {
                    if (t != null && t.id != trip.id) {
                      _selectTrip(t);
                    }
                  },
                ),
              ),
            ),
          NkCard(
            padding: const EdgeInsets.all(14),
            color: NkColors.primaryBlue.withValues(alpha: 0.06),
            child: Text(
              'Registrer hvordan turen faktisk gikk. Erfaringene lagres på turen og hjelper deg å planlegge bedre neste gang. '
              'Ubrukt sikkerhetsutstyr anbefales likevel med på fremtidige turer.',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
          ),
          const SizedBox(height: 14),
          NkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  'Faktisk gjennomføring',
                  icon: Icons.fact_check_outlined,
                ),
                if (_prefilledFromTrack) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Forhåndsutfylt fra GPS-sporet ditt – juster om noe ikke stemmer.',
                    style: TextStyle(
                      fontSize: 11,
                      color: NkColors.forestGreen,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _distance,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Distanse (km)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _duration,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Varighet (t)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ascent,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Stigning (m)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _weather,
                  decoration: const InputDecoration(
                    labelText: 'Vær opplevd',
                    hintText: 'F.eks. sol første dag, regn og vind dag 2',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _difficult,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Krevende partier',
                    hintText: 'Hvor var det tungt eller krevende?',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Helhetsinntrykk: ',
                      style: TextStyle(fontSize: 13),
                    ),
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          i <= _rating ? Icons.star : Icons.star_border,
                          color: NkColors.warningAmber,
                          size: 24,
                        ),
                        onPressed: () => setState(() => _rating = i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          NkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader('Utstyr', icon: Icons.backpack_outlined),
                const SizedBox(height: 10),
                _ItemPicker(
                  label: 'Utstyr som fungerte godt',
                  items: _workedWell,
                  suggestions: _packingNames(trip),
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                _ItemPicker(
                  label: 'Unødvendig utstyr',
                  items: _unnecessary,
                  suggestions: _packingNames(trip),
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                _ItemPicker(
                  label: 'Utstyr som manglet',
                  items: _missing,
                  suggestions: _packingNames(trip),
                  allowCustom: true,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          NkCard(
            child: TextField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Generelle notater',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _save(trip),
            icon: const Icon(Icons.check),
            label: const Text('Lagre evaluering'),
          ),
          const SizedBox(height: 8),
          Text(
            'Turen markeres som «${TripStatus.completed.label}» når du lagrer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
          ),
        ],
      ),
    );
  }

  List<String> _packingNames(Trip trip) =>
      trip.packingList.map((i) => i.name).toSet().toList()..sort();

  Future<void> _save(Trip trip) async {
    for (final field in [_distance, _duration, _ascent]) {
      if (field.text.trim().isEmpty) continue;
      final value = double.tryParse(field.text.replaceAll(',', '.'));
      if (value == null || !value.isFinite || value < 0) {
        nkToast(
          context,
          'Distanse, tid og stigning må være positive tall eller stå tomme.',
        );
        return;
      }
    }
    final review = TripReview(
      actualDistanceKm: double.tryParse(_distance.text.replaceAll(',', '.')),
      actualDurationHours: double.tryParse(_duration.text.replaceAll(',', '.')),
      actualAscent: double.tryParse(_ascent.text.replaceAll(',', '.')),
      weatherExperienced: _weather.text.trim(),
      workedWell: List.of(_workedWell),
      unnecessary: List.of(_unnecessary),
      missing: List.of(_missing),
      difficultSections: _difficult.text.trim(),
      notes: _notes.text.trim(),
      rating: _rating,
      completedAt: DateTime.now(),
    );
    await context.read<AppState>().saveReview(trip, review);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evaluering lagret – takk!')),
      );
      Navigator.pop(context);
    }
  }
}

/// Chip-based item picker: shows selected items as removable chips
/// and offers the trip's packing list as suggestions, so names match
/// what the packing engine learns from. Custom entries are allowed
/// when [allowCustom] is set (e.g. gear that wasn't on the list).
class _ItemPicker extends StatelessWidget {
  final String label;
  final List<String> items;
  final List<String> suggestions;
  final bool allowCustom;
  final VoidCallback onChanged;

  const _ItemPicker({
    required this.label,
    required this.items,
    required this.suggestions,
    required this.onChanged,
    this.allowCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              InputChip(
                label: Text(item, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onDeleted: () {
                  items.remove(item);
                  onChanged();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Legg til', style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _add(context),
            ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Trykk «Legg til» for å velge fra pakkelisten',
              style: TextStyle(
                fontSize: 10,
                color: NkColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final available = suggestions.where((s) => !items.contains(s)).toList();
    final custom = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(label),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in available)
                  ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.pop(ctx, s),
                  ),
                if (allowCustom) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: custom,
                      decoration: const InputDecoration(
                        labelText: 'Annet (fritekst)',
                        hintText: 'F.eks. solkrem',
                      ),
                      onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null && picked.isNotEmpty && !items.contains(picked)) {
      items.add(picked);
      onChanged();
    }
  }
}
