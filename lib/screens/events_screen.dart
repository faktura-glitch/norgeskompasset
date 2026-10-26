import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/calendar_event.dart';
import '../state/app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';

const _months = [
  'januar',
  'februar',
  'mars',
  'april',
  'mai',
  'juni',
  'juli',
  'august',
  'september',
  'oktober',
  'november',
  'desember',
];

String _monthLabel(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String _when(CalendarEvent e) {
  if (e.formatted != null && e.formatted!.isNotEmpty) return e.formatted!;
  final time =
      '${e.start.hour.toString().padLeft(2, '0')}:${e.start.minute.toString().padLeft(2, '0')}';
  if (e.multiDay) return '${fmtDate(e.start)} – ${fmtDate(e.end)}';
  return '${fmtDate(e.start)} kl. $time';
}

/// The NorgesKompasset tour calendar: upcoming arrangements from
/// norgeskompasset.no, grouped by month.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  EventKind? _kind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AppState>().loadEvents(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final events = state.events
        .where((e) => !e.isPast && (_kind == null || e.kind == _kind))
        .toList();
    final groups = <String, List<CalendarEvent>>{};
    for (final e in events) {
      groups.putIfAbsent(_monthLabel(e.start), () => []).add(e);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Turkalender'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            icon: const Icon(Icons.refresh),
            onPressed: state.eventsLoading
                ? null
                : () => state.loadEvents(force: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => state.loadEvents(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'Fellesturer og treff arrangert av NorgesKompasset. Påmelding '
              'skjer på norgeskompasset.no.',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alle'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
                for (final k in EventKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            if (state.eventsLoading && state.events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (state.eventsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.eventsError!,
                  style: TextStyle(fontSize: 12, color: NkColors.warningAmber),
                ),
              ),
            if (!state.eventsLoading &&
                state.eventsError == null &&
                events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('Ingen kommende arrangementer i dette utvalget.'),
              ),
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 6),
                child: Text(
                  entry.key[0].toUpperCase() + entry.key.substring(1),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final e in entry.value) EventCard(event: e),
            ],
            if (state.eventsFetchedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Sist hentet ${fmtDateTime(state.eventsFetchedAt)}',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  final CalendarEvent event;
  final bool compact;
  const EventCard({super.key, required this.event, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final e = event;
    return NkCard(
      onTap: () => showEventDetails(context, e),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact && e.image != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: CachedNetworkImage(
                imageUrl: e.image!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: NkColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NkColors.border),
                      ),
                      child: Text(
                        e.kind.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_when(e), style: const TextStyle(fontSize: 13)),
                if (e.place.isNotEmpty)
                  Text(
                    e.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: NkColors.textSecondary,
                    ),
                  ),
                if (e.priceLabel.isNotEmpty || e.soldOut)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      e.soldOut ? 'Utsolgt' : e.priceLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: e.soldOut
                            ? NkColors.dangerRed
                            : NkColors.forestGreen,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showEventDetails(BuildContext context, CalendarEvent e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            e.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(_when(e), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (e.place.isNotEmpty)
            Text(
              'Oppmøte: ${e.place}',
              style: TextStyle(color: NkColors.textSecondary),
            ),
          if (e.priceLabel.isNotEmpty || e.soldOut)
            Text(
              e.soldOut ? 'Utsolgt' : e.priceLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.description),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(e.url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Les mer og meld deg på'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final state = context.read<AppState>();
              await state.startFromEvent(e);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              context.read<NavController>().goTo(2);
              nkToast(
                context,
                'Turutkast opprettet – tegn ruten på kartet, så følger '
                'pakkeliste og vær med.',
              );
            },
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Planlegg denne turen i appen'),
          ),
          const SizedBox(height: 6),
          Text(
            'Appen lager et turutkast med navn, datoer og oppmøtested. '
            'Påmelding og betaling skjer på norgeskompasset.no.',
            style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

/// Compact teaser for the Turer tab: next three arrangements.
class EventsTeaser extends StatelessWidget {
  const EventsTeaser({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final next = state.events.where((e) => !e.isPast).take(3).toList();
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  'Turkalender – bli med på tur',
                  icon: Icons.event_outlined,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EventsScreen()),
                ),
                child: const Text('Se alle'),
              ),
            ],
          ),
          if (next.isEmpty)
            Text(
              state.eventsLoading
                  ? 'Henter arrangementer …'
                  : (state.eventsError ??
                        'Ingen kommende arrangementer akkurat nå.'),
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            )
          else
            for (final e in next)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(switch (e.kind) {
                  EventKind.tur => Icons.hiking,
                  EventKind.treff => Icons.local_cafe_outlined,
                  EventKind.camp => Icons.cabin_outlined,
                }, color: NkColors.primaryBlue),
                title: Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${fmtDate(e.start)}${e.locationName != null ? ' · ${e.locationName}' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showEventDetails(context, e),
              ),
        ],
      ),
    );
  }
}
