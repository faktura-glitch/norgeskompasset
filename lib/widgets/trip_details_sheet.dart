import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/trip.dart';
import '../state/app_state.dart';

/// Name, notes and «hjemme senest» — trip details that don't belong on
/// the map. Opened from the trip card on Hjem and the planner panel.
Future<void> showTripDetailsSheet(BuildContext context, Trip trip) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TripDetailsSheet(trip: trip),
  );
}

class _TripDetailsSheet extends StatefulWidget {
  final Trip trip;
  const _TripDetailsSheet({required this.trip});

  @override
  State<_TripDetailsSheet> createState() => _TripDetailsSheetState();
}

class _TripDetailsSheetState extends State<_TripDetailsSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.trip.name,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.trip.notes,
  );

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickExpectedReturn() async {
    final trip = widget.trip;
    final day = await showDatePicker(
      context: context,
      initialDate: trip.expectedReturn ?? trip.endDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 540)),
      helpText: 'Hjemme senest – dato',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        trip.expectedReturn ?? day.add(const Duration(hours: 18)),
      ),
      helpText: 'Hjemme senest – klokkeslett',
    );
    if (time == null || !mounted) return;
    setState(() {
      trip.expectedReturn = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final trip = widget.trip;
    trip.name = _name.text.trim();
    trip.notes = _notes.text.trim();
    await context.read<AppState>().saveTrip(trip);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final hasReturn = trip.expectedReturn != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turdetaljer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Turnavn'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notater (valgfritt)',
                  hintText: 'Erfaring, utstyr, avtaler…',
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickExpectedReturn,
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Hjemme senest (valgfritt)',
                    helperText:
                        'Turmodus varsler deg hvis tiden passerer mens du '
                        'fortsatt er ute',
                    suffixIcon: Icon(Icons.schedule, size: 16),
                  ),
                  child: Text(
                    hasReturn ? fmtDateTime(trip.expectedReturn!) : 'Ikke satt',
                    style: TextStyle(
                      fontSize: 13,
                      color: hasReturn
                          ? NkColors.textPrimary
                          : NkColors.textSecondary,
                    ),
                  ),
                ),
              ),
              if (hasReturn)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => trip.expectedReturn = null),
                    child: const Text('Fjern'),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Lagre'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
