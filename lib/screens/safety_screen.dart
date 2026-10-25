import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../models/route_models.dart';
import '../models/trip.dart';
import '../services/gpx_service.dart';
import '../services/weather_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class SafetyScreen extends StatelessWidget {
  final bool emergencyFirst;
  const SafetyScreen({super.key, this.emergencyFirst = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    return Scaffold(
      appBar: AppBar(title: tripScreenTitle('Del tur og sikkerhet', trip)),
      body: trip == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [_EmergencyCard()],
            )
          : ListView(
              padding: EdgeInsets.all(wide ? 28 : 16),
              children: [
                if (emergencyFirst) ...[
                  const _EmergencyCard(),
                  const SizedBox(height: 16),
                ],
                ScreenBanner(
                  url: NkImages.jotunheimen,
                  title: 'Del planen – gå trygt',
                  subtitle:
                      'for «${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» — turkort, nødnumre og offline kart',
                  height: 120,
                ),
                const SizedBox(height: 14),
                _TripCard(trip: trip),
                const SizedBox(height: 16),
                _OfflineMapCard(trip: trip),
                const SizedBox(height: 16),
                if (!emergencyFirst) ...[
                  const _EmergencyCard(),
                  const SizedBox(height: 16),
                ],
                _CheckInCard(trip: trip),
              ],
            ),
    );
  }
}

class _TripCard extends StatefulWidget {
  final Trip trip;
  const _TripCard({required this.trip});

  @override
  State<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<_TripCard> {
  bool _includeIce = false;
  bool _includeMedical = false;
  Trip get trip => widget.trip;

  String _summary(UserProfile profile) {
    final b = StringBuffer();
    b.writeln('TURKORT – ${trip.name.isEmpty ? 'Tur uten navn' : trip.name}');
    if (profile.name.isNotEmpty) {
      b.writeln(
        'Navn: ${profile.name}'
        '${profile.phone.isNotEmpty ? ' · ${profile.phone}' : ''}',
      );
    }
    if (_includeIce &&
        (profile.iceName.isNotEmpty || profile.icePhone.isNotEmpty)) {
      b.writeln(
        'Nødkontakt: ${profile.iceName}'
        '${profile.icePhone.isNotEmpty ? ' · ${profile.icePhone}' : ''}',
      );
    }
    if (_includeMedical && profile.medicalNotes.isNotEmpty) {
      b.writeln('Medisinsk info: ${profile.medicalNotes}');
    }
    b.writeln(
      'Periode: ${fmtDate(trip.startDate)} – ${fmtDate(trip.endDate)} (${fmtCount(trip.hikingDays, 'dag', 'dager')})',
    );
    if (trip.route?.hasRoute == true) {
      final r = trip.route!;
      b.writeln(
        'Rute: ${fmtKm(r.distanceMeters)}'
        '${r.waypoints.isNotEmpty ? ' – ${r.waypoints.first.name} → ${r.waypoints.last.name}' : ''}',
      );
      b.writeln('Rutestatus: ${r.sourceLabel}');
      if (r.start != null) {
        b.writeln(
          'Start: ${r.start!.latitude.toStringAsFixed(5)}, ${r.start!.longitude.toStringAsFixed(5)}',
        );
        b.writeln(
          'Mål: ${r.end!.latitude.toStringAsFixed(5)}, ${r.end!.longitude.toStringAsFixed(5)}',
        );
      }
    }
    if (trip.stages.isNotEmpty) {
      b.writeln('Etapper:');
      for (final s in trip.stages) {
        b.writeln(
          '  ${s.number}. ${fmtDate(s.date)} – ${s.startName} → ${s.endName} (${fmtKm(s.distanceMeters)})',
        );
      }
    }
    final overnights =
        trip.route?.waypoints
            .where((w) => w.type == WaypointType.overnight)
            .map((w) => w.name)
            .toList() ??
        [];
    if (overnights.isNotEmpty) {
      b.writeln('Overnattinger: ${overnights.join(', ')}');
    }
    b.writeln('Overnattingstype: ${trip.accommodation.label}');
    b.writeln('Aktivitet: ${trip.activity.label}');
    b.writeln('Sesong/bæring: ${trip.season.label} · ${trip.carry.label}');
    b.writeln('Deltakere: ${trip.participants}');
    if (trip.notes.isNotEmpty) b.writeln('Notater: ${trip.notes}');
    b.writeln(
      '\nSendt fra NorgesKompasset – planlagt retur ${fmtDate(trip.endDate)}.',
    );
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Turkort for trygge kontakter',
            icon: Icons.share_outlined,
          ),
          const SizedBox(height: 6),
          Text(
            'Del turplanen din med noen du stoler på. Den inneholder rute, datoer og forventet retur – slik at andre vet hvor du er og når du skal være tilbake.',
            style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ta med nødkontakt'),
            value: _includeIce,
            onChanged: (v) => setState(() => _includeIce = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ta med medisinske opplysninger'),
            subtitle: const Text('Del bare med noen du stoler på.'),
            value: _includeMedical,
            onChanged: (v) => setState(() => _includeMedical = v),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NkColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NkColors.border),
            ),
            child: Text(
              _summary(context.read<AppState>().profile),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
          if (trip.lastSharedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Sist delt: ${fmtDateTime(trip.lastSharedAt)}',
              style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'GPX-eksport: ruten kan lastes ned og importeres i UT.no, Garmin, Strava og lignende.',
            style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final result = await SharePlus.instance.share(
                      ShareParams(
                        text: _summary(context.read<AppState>().profile),
                      ),
                    );
                    if (!context.mounted) return;
                    if (result.status == ShareResultStatus.success) {
                      trip.lastSharedAt = DateTime.now();
                      await context.read<AppState>().saveTrip(trip);
                    } else if (result.status == ShareResultStatus.unavailable) {
                      nkToast(
                        context,
                        'Delingsmenyen er åpnet. Appen kan ikke bekrefte sending.',
                      );
                    }
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Del turplan'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Kopier til utklippstavle',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: _summary(context.read<AppState>().profile),
                    ),
                  );
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Kopiert')));
                },
              ),
              IconButton(
                tooltip: 'Eksporter rute som GPX',
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _exportGpx(context),
              ),
              if (trip.trackLog.length >= 2)
                IconButton(
                  tooltip:
                      'Eksporter gått spor som GPX (${trip.trackLog.length} punkter)',
                  icon: const Icon(Icons.route_outlined),
                  onPressed: () => _exportTrackGpx(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportTrackGpx(BuildContext context) async {
    try {
      final path = await GpxService.exportTrackToDownloads(trip);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Spor lagret: $path')));
    } on ServiceException catch (e) {
      if (!context.mounted) return;
      final gpx = GpxService.trackToGpx(trip);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Spor (GPX)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.message, style: const TextStyle(fontSize: 12)),
              if (gpx != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      gpx,
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Lukk'),
            ),
            if (gpx != null)
              FilledButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: gpx));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('GPX kopiert')));
                },
                child: const Text('Kopier GPX'),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _exportGpx(BuildContext context) async {
    try {
      final path = await GpxService.exportToDownloads(trip);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('GPX lagret: $path')));
    } on ServiceException catch (e) {
      if (!context.mounted) return;
      // Fallback: offer the raw GPX text so nothing is lost on web.
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('GPX'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.message, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: SelectableText(
                    GpxService.toGpx(trip),
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Lukk'),
            ),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: GpxService.toGpx(trip)));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('GPX kopiert')));
              },
              child: const Text('Kopier GPX'),
            ),
          ],
        ),
      );
    }
  }
}

class _OfflineMapCard extends StatelessWidget {
  final Trip trip;
  const _OfflineMapCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasRoute = trip.route?.hasRoute == true;
    final coverage = state.offlineCoverage(trip);
    final done = state.tilesDone;
    final total = state.tilesTotal;
    final downloading = total != null && done != null;

    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Offline kart',
            icon: Icons.download_for_offline_outlined,
          ),
          const SizedBox(height: 6),
          Text(
            'Last ned kartflisene langs ruten på forhånd – da virker kartet i turmodus selv uten dekning. Dekker området rundt ruten på detaljnivå.',
            style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.storage_outlined,
                size: 16,
                color: NkColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasRoute
                      ? 'Lagret for dette utsnittet: ${coverage.cached}/${coverage.total} fliser. Gjelder valgte zoomnivåer, ikke alle kartlag. Test i flymodus.'
                      : '${state.mapTilesCached} kartfliser lagret i hurtiglageret',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            NkProgress(total == 0 ? 0 : done / total),
            const SizedBox(height: 4),
            Text(
              '$done/$total fliser',
              style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          if (downloading)
            OutlinedButton.icon(
              onPressed: state.cancelMapDownload,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Avbryt nedlasting'),
            )
          else
            FilledButton.icon(
              onPressed: hasRoute ? () => state.downloadMapTiles(trip) : null,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(
                hasRoute ? 'Last ned kartet for turen' : 'Beregn en rute først',
              ),
            ),
        ],
      ),
    );
  }
}

class _EmergencyPosition extends StatefulWidget {
  const _EmergencyPosition();

  @override
  State<_EmergencyPosition> createState() => _EmergencyPositionState();
}

class _EmergencyPositionState extends State<_EmergencyPosition> {
  Position? _position;
  bool _loading = false;
  String? _error;

  Future<void> _locate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ServiceException(
          'Gi posisjonstilgang i telefonens innstillinger.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) setState(() => _position = position);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Posisjon utilgjengelig. Sjekk GPS og tilgang, eller oppgi kjent sted.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_position case final p?)
        SelectableText(
          'Posisjon: ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}\n'
          'Nøyaktighet ±${p.accuracy.round()} m · ${fmtDateTime(p.timestamp)}',
        ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: NkColors.dangerRed)),
      OutlinedButton.icon(
        onPressed: _loading ? null : _locate,
        icon: const Icon(Icons.my_location),
        label: Text(_loading ? 'Henter posisjon …' : 'Vis min posisjon'),
      ),
      const Text('Oppgi posisjonen til nødetaten. Den sendes ikke automatisk.'),
    ],
  );
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard();

  Future<void> _call(BuildContext context, String number) async {
    try {
      final launched = await launchUrl(Uri.parse('tel:$number'));
      if (!launched && context.mounted) {
        nkToast(context, 'Ring $number manuelt fra telefonen.');
      }
    } catch (_) {
      if (context.mounted) {
        nkToast(context, 'Kunne ikke åpne telefonen. Ring $number manuelt.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Nødnumre i Norge',
            icon: Icons.emergency_outlined,
          ),
          const SizedBox(height: 12),
          const _EmergencyPosition(),
          const SizedBox(height: 6),
          Text(
            'Ved skade eller fare i fjellet: ring først 113 (medisinsk) eller 112 (politi). Hjelpekort: oppgi posisjon (koordinater eller sted), hva som har skjedd, og antall personer.',
            style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 10),
          for (final (num, label, desc) in [
            ('113', 'Medisinsk nødhjelp', 'Alvorlig sykdom/skade – AMK'),
            ('112', 'Politi', 'Fjellredning, vold, umiddelbar fare'),
            ('110', 'Brann', 'Brann og akutte ulykker'),
            (
              '1412',
              'Nødsamtale via teksttelefon',
              '1412 er teksttelefon, ikke Nød-SMS',
            ),
            (
              '116117',
              'Legevakt',
              'Ved ikke-livstruende sykdom utenom åpningstid',
            ),
          ])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: num == '113' || num == '112'
                    ? NkColors.dangerRed
                    : NkColors.primaryBlue,
                child: Text(
                  num,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(desc, style: const TextStyle(fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(
                  Icons.phone_outlined,
                  color: NkColors.forestGreen,
                ),
                onPressed: () => _call(context, num),
              ),
            ),
          const Divider(),
          const Text(
            'Nød-SMS: Registrerte døve, hørselshemmede og talehemmede '
            'kan sende SMS til 110, 112 eller 113. Tjenesten krever forhåndsregistrering.',
          ),
          Text(
            'Ved akutt fare: kontakt nødetatene, som vurderer behov for redningsinnsats. Knappene åpner telefonen – de sender ikke automatisk posisjon eller varsel.',
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

class _CheckInCard extends StatefulWidget {
  final Trip trip;
  const _CheckInCard({required this.trip});

  @override
  State<_CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<_CheckInCard> {
  bool _fetching = false;

  /// Shares the current GPS position as an "I'm OK" check-in —
  /// the simplest possible safety loop for a trusted contact.
  Future<void> _sharePosition() async {
    setState(() => _fetching = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Ingen posisjonstilgang – kan ikke dele posisjon.');
        return;
      }
      // Prefer a fresh fix; fall back to last known if the device
      // is under cover / has weak sky view.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        _toast('Fikk ingen posisjon – prøv igjen ute i fri sikt.');
        return;
      }
      final t = widget.trip;
      final text = StringBuffer()
        ..writeln('Jeg er i rute – ${t.name.isEmpty ? 'fjelltur' : t.name}')
        ..writeln(
          'Posisjon: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
        )
        ..writeln(
          'Kart: https://www.google.com/maps/search/?api=1'
          '&query=${pos.latitude},${pos.longitude}',
        )
        ..writeln('Tidspunkt: ${fmtDateTime(pos.timestamp)}')
        ..writeln('Planlagt retur: ${fmtDate(t.endDate)}');
      await SharePlus.instance.share(ShareParams(text: '$text'));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    nkToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Innsjekking og retur', icon: Icons.alarm),
          const SizedBox(height: 6),
          Text(
            'Tips til plan: avtal faste innsjekk-tidspunkter med kontakten din (f.eks. morgen og kveld), og avtal hva de skal gjøre hvis du ikke sjekker inn innen en gitt tid.',
            style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.event_available,
                size: 16,
                color: NkColors.primaryBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Planlagt retur: ${fmtDate(trip.endDate)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _fetching ? null : _sharePosition,
              icon: _fetching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location, size: 18),
              label: const Text('Jeg er i rute – del posisjon'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lokasjonsdeling: posisjonen deles kun når du trykker – det er ingen kontinuerlig sporing eller automatisk varsling.',
            style: TextStyle(
              fontSize: 11,
              color: NkColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
