import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/stage.dart';
import '../models/trip.dart';
import '../models/weather.dart';
import '../services/trip_analysis.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  int _selectedStage = 0;
  String? _weatherError;

  Future<void> _refreshWeather(Trip trip) async {
    final state = context.read<AppState>();
    await state.fetchWeather(trip);
    if (mounted) setState(() => _weatherError = state.lastError);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    if (trip == null || (trip.stages.isEmpty && trip.route?.hasRoute != true)) {
      return Scaffold(
        appBar: AppBar(title: tripScreenTitle('Vær langs ruten', trip)),
        body: const EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Ingen rute å hente vær for',
          message: 'Værprognosen hentes for punkter langs den planlagte ruten. Planlegg en rute først.',
        ),
      );
    }

    final stages = trip.stages;
    if (_selectedStage >= stages.length) _selectedStage = 0;

    return Scaffold(
      appBar: AppBar(
        title: tripScreenTitle('Vær langs ruten', trip),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Hent oppdatert prognose',
            onPressed: state.busy ? null : () => _refreshWeather(trip),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshWeather(trip),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            ScreenBanner(
              url: NkImages.lofoten,
              title: 'Vær langs ruten',
              subtitle:
                  'for «${trip.name.isEmpty ? 'Tur uten navn' : trip.name}» — MET Norway · varsom.no',
            ),
            const SizedBox(height: 14),
            Text(
              'Turperiode: ${fmtDate(trip.startDate)} – ${fmtDate(trip.endDate)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (bestHikingDay(trip.weather['route']?.hours ?? const [])
                case final best?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NkCard(
                  color: NkColors.forestGreen.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wb_sunny_outlined,
                        color: NkColors.forestGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Beste dag å gå (estimert): ${fmtDate(best.day)} – '
                          '${best.reason}.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.busy) const LinearProgressIndicator(),
            if (_weatherError != null)
              NkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_weatherError!),
                    const Text(
                      'Eventuelt tidligere hentet vær vises fortsatt. Kontroller dato og alder.',
                    ),
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => _refreshWeather(trip),
                      child: const Text('Prøv igjen'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // Stage selector
            if (stages.isNotEmpty) ...[
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stages.length,
                  separatorBuilder: (a, b) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ChoiceChip(
                    label: Text(
                      'Etappe ${stages[i].number}${stages[i].date != null ? ' · ${fmtDate(stages[i].date)}' : ''}',
                    ),
                    selected: _selectedStage == i,
                    onSelected: (_) => setState(() => _selectedStage = i),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (stages.isNotEmpty)
              _StageWeather(
                stage: stages[_selectedStage],
                trip: trip,
                onRefresh: () => _refreshWeather(trip),
              )
            else
              _StageWeather(
                stage: null,
                trip: trip,
                onRefresh: () => _refreshWeather(trip),
              ),
          ],
        ),
      ),
    );
  }
}

/// MET symbol codes (e.g. "lightrain_night") → Norwegian labels.
String symbolLabel(String code) {
  final base = code.replaceAll(RegExp(r'_(day|night|polartwilight)$'), '');
  const labels = {
    'clearsky': 'Klarvær',
    'fair': 'Lettskyet',
    'partlycloudy': 'Delvis skyet',
    'cloudy': 'Skyet',
    'fog': 'Tåke',
    'lightrainshowers': 'Lette regnbyger',
    'rainshowers': 'Regnbyger',
    'heavyrainshowers': 'Kraftige regnbyger',
    'lightrain': 'Lett regn',
    'rain': 'Regn',
    'heavyrain': 'Kraftig regn',
    'lightsleet': 'Lett sludd',
    'sleet': 'Sludd',
    'heavysleet': 'Kraftig sludd',
    'lightsnow': 'Lett snøfall',
    'snow': 'Snø',
    'heavysnow': 'Kraftig snøfall',
    'lightsnowshowers': 'Lette snøbyger',
    'snowshowers': 'Snøbyger',
    'heavysnowshowers': 'Kraftige snøbyger',
    'rainandthunder': 'Regn og torden',
    'snowandthunder': 'Snø og torden',
    'sleetandthunder': 'Sludd og torden',
    'lightrainshowersandthunder': 'Lette regnbyger og torden',
    'rainshowersandthunder': 'Regnbyger og torden',
    'heavyrainshowersandthunder': 'Kraftige regnbyger og torden',
    'lightsnowshowersandthunder': 'Lette snøbyger og torden',
    'snowshowersandthunder': 'Snøbyger og torden',
    'heavysnowshowersandthunder': 'Kraftige snøbyger og torden',
  };
  return labels[base] ?? base;
}

class _StageWeather extends StatelessWidget {
  final Stage? stage;
  final Trip trip;
  final VoidCallback onRefresh;
  const _StageWeather({
    required this.stage,
    required this.trip,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final snaps = stage != null
        ? TripAnalysis.snapshotsForStage(trip, stage!)
        : trip.weather.values.toList();
    final (from, to) = stage != null
        ? TripAnalysis.stageWindow(stage!, trip)
        : (DateTime.now(), DateTime.now().add(const Duration(days: 1)));

    if (snaps.isEmpty) {
      return NkCard(
        child: Column(
          children: [
            const Icon(
              Icons.cloud_download_outlined,
              size: 40,
              color: NkColors.primaryBlue,
            ),
            const SizedBox(height: 10),
            const Text(
              'Ingen prognose hentet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Hent fersk prognose fra MET Norway for punkt langs etappen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Hent prognose'),
            ),
          ],
        ),
      );
    }

    final snap = snaps.first;
    final summary = TripAnalysis.summarize(snaps, from, to);
    final beyond = TripAnalysis.beyondForecast(snap, from);
    final dayHours = snap.hoursBetween(from, to);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Official warnings (MET metalerts) covering this stage window
        _OfficialAlerts(trip: trip, from: from, to: to),
        if (trip.alerts.any((a) => a.covers(from) || a.covers(to)))
          const SizedBox(height: 12),
        // Avalanche warnings (Varsom/NVE) for the same window
        _AvalancheAlerts(trip: trip, from: from, to: to),
        if (trip.avalancheWarnings.any(
          (w) => _overlaps(w.validFrom, w.validTo, from, to),
        ))
          const SizedBox(height: 12),

        // Data quality / freshness card
        NkCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.satellite_alt_outlined,
                    size: 16,
                    color: NkColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kilde: ${snap.source}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                snaps.length > 1
                    ? 'Basert på ${snaps.length} prognosepunkter langs etappen '
                          '(start, midten, slutt)'
                    : 'Prognosepunkt: ${snap.lat.toStringAsFixed(3)}, ${snap.lon.toStringAsFixed(3)}'
                          '${snap.elevation != null ? ' · ${snap.elevation!.round()} moh' : ''}'
                          ' – ${stage != null ? 'nær midtpunktet av etappen' : 'langs ruten'}',
                style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
              ),
              Text(
                'Hentet ${fmtAge(snap.retrievedAt)}'
                '${snap.forecastIssuedAt != null ? ' · modell kjørt ${fmtDateTime(snap.forecastIssuedAt)}' : ''}'
                '${snap.forecastHorizon != null ? ' · prognose til ${fmtDateTime(snap.forecastHorizon)}' : ''}',
                style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (!summary.hasData || beyond) ...[
          NkCard(
            color: NkColors.warningAmber.withValues(alpha: 0.08),
            child: const Row(
              children: [
                Icon(Icons.schedule_outlined, color: NkColors.warningAmber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Denne dagen ligger utenfor prognosens rekkevidde (ca. 9 dager). Sjekk været på nytt nærmere avreise – langtidsvarsel i fjellet er usikkert.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (summary.hasData) ...[
          // Summary tiles
          NkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  'Dagsoversikt',
                  icon: Icons.wb_sunny_outlined,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    InfoTile(
                      'Temperatur',
                      '${fmtTemp(summary.minTemp)} – ${fmtTemp(summary.maxTemp)}',
                      icon: Icons.thermostat,
                    ),
                    InfoTile(
                      'Nedbør',
                      fmtPrecip(summary.totalPrecipMm),
                      icon: Icons.water_drop_outlined,
                      valueColor: summary.rainExpected
                          ? NkColors.warningAmber
                          : null,
                    ),
                    InfoTile(
                      'Vind',
                      fmtWind(summary.maxWind),
                      icon: Icons.air,
                      valueColor: summary.strongWind
                          ? NkColors.dangerRed
                          : null,
                    ),
                    InfoTile(
                      'Vindkast',
                      fmtWind(summary.maxGust),
                      icon: Icons.storm,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Alerts(summary: summary),
          const SizedBox(height: 12),
          // Hourly timeline grouped into periods
          _Timeline(hours: dayHours),
          const SizedBox(height: 12),
          NkCard(
            padding: EdgeInsets.all(12),
            child: Text(
              'Prognosen gjelder for ett punkt langs etappen – forhold kan variere betydelig med høyde og terreng. Fravær av varsel betyr ikke at forholdene er trygge.',
              style: TextStyle(
                fontSize: 11,
                color: NkColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OfficialAlerts extends StatelessWidget {
  final Trip trip;
  final DateTime from;
  final DateTime to;
  const _OfficialAlerts({
    required this.trip,
    required this.from,
    required this.to,
  });

  static const _levelColors = {
    1: NkColors.forestGreen,
    2: NkColors.warningAmber,
    3: Color(0xFFD35400), // orange
    4: NkColors.dangerRed,
  };

  @override
  Widget build(BuildContext context) {
    // Warnings overlapping the stage window
    final alerts = trip.alerts
        .where((a) => a.covers(from) || a.covers(to))
        .toList();
    if (alerts.isEmpty) return const SizedBox.shrink();
    return NkCard(
      color: NkColors.dangerRed.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Offisielle varsler (MET/NVE)',
            icon: Icons.campaign_outlined,
          ),
          const SizedBox(height: 8),
          for (final a in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color:
                            _levelColors[a.awarenessLevel] ??
                            NkColors.warningAmber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${a.levelLabel}: ${a.title}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (a.area.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 2),
                      child: Text(
                        a.area,
                        style: TextStyle(
                          fontSize: 11,
                          color: NkColors.textSecondary,
                        ),
                      ),
                    ),
                  if (a.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Text(
                        a.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (a.instruction.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Text(
                        'Anbefaling: ${a.instruction}',
                        style: TextStyle(
                          fontSize: 12,
                          color: NkColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Text(
            'Varslene gjelder for området rundt etappen – vurder alltid lokale forhold selv.',
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

/// Whether a warning's [wFrom]–[wTo] validity overlaps the stage
/// window [from]–[to]. Open-ended bounds count as covering.
bool _overlaps(DateTime? wFrom, DateTime? wTo, DateTime from, DateTime to) {
  if (wFrom != null && wFrom.isAfter(to)) return false;
  if (wTo != null && wTo.isBefore(from)) return false;
  return true;
}

/// Avalanche warnings from Varsom/NVE for the stage's date window.
/// Hidden entirely when there are none (out of season or beyond
/// the published horizon) — never shows stale or implied safety.
class _AvalancheAlerts extends StatelessWidget {
  final Trip trip;
  final DateTime from;
  final DateTime to;
  const _AvalancheAlerts({
    required this.trip,
    required this.from,
    required this.to,
  });

  static const _levelColors = <int, Color>{
    1: NkColors.forestGreen,
    2: NkColors.warningAmber,
    3: Color(0xFFE0701A), // orange — EAWS level 3
    4: NkColors.dangerRed,
    5: Color(0xFF7B1113), // deep red — EAWS level 5
  };

  @override
  Widget build(BuildContext context) {
    final warnings =
        trip.avalancheWarnings
            .where((w) => _overlaps(w.validFrom, w.validTo, from, to))
            .toList()
          ..sort((a, b) => (b.dangerLevel).compareTo(a.dangerLevel));
    if (warnings.isEmpty) return const SizedBox.shrink();
    return NkCard(
      color: NkColors.warningAmber.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Snøskredvarsel (varsom.no)',
            icon: Icons.ac_unit_outlined,
          ),
          const SizedBox(height: 8),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color:
                            _levelColors[w.dangerLevel] ??
                            NkColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${w.levelLabel}: ${w.regionName}'
                          '${w.validFrom != null ? ' · ${fmtDate(w.validFrom)}' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (w.mainText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Text(
                        w.mainText,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          Text(
            'Varsler fra Snøskredvarslingen i Norge og www.varsom.no. Les hele varselet på varsom.no – kortversjonen utelater utsatte heydersoner og skredproblemer.',
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

class _Alerts extends StatelessWidget {
  final ConditionsSummary summary;
  const _Alerts({required this.summary});

  @override
  Widget build(BuildContext context) {
    final alerts = <(IconData, Color, String)>[
      if (summary.rainExpected)
        (
          Icons.water_drop,
          NkColors.warningAmber,
          'Nedbør ventet (${summary.totalPrecipMm.toStringAsFixed(1)} mm) – våt sti og behov for regntøy.',
        ),
      if (summary.strongWind)
        (
          Icons.air,
          NkColors.dangerRed,
          'Kraftig vind (opptil ${fmtWind(summary.maxWind)}) – eksponerte partier kan bli vanskelige.',
        ),
      if (summary.freezingTemps)
        (
          Icons.ac_unit,
          NkColors.primaryBlue,
          'Temperaturer ned mot ${fmtTemp(summary.minTemp)} – mulig frost i høyden.',
        ),
      if (summary.limitedVisibility)
        (
          Icons.foggy,
          NkColors.warningAmber,
          'Skydekke over 95 % med nedbør i ${summary.lowVisHours} av timene kan '
              'gi dårlig sikt – et grovt anslag, sikt varsles ikke direkte.',
        ),
      if (summary.maxTemp != null && summary.maxTemp! > 22)
        (
          Icons.wb_sunny,
          NkColors.warningAmber,
          'Varmt (opptil ${fmtTemp(summary.maxTemp)}) – husk solskjerming og ekstra vann.',
        ),
    ];
    if (alerts.isEmpty) {
      return NkCard(
        color: NkColors.forestGreen.withValues(alpha: 0.08),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: NkColors.forestGreen,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ingen spesielle værforhold avdekket for denne perioden. Husk at fjellvær kan endre seg raskt.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final (icon, color, text) in alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NkCard(
              color: color.withValues(alpha: 0.08),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<WeatherHour> hours;
  const _Timeline({required this.hours});

  @override
  Widget build(BuildContext context) {
    // Split the stage day into 4 periods: morning/day/evening/night.
    final periods = <(String, IconData, int, int)>[
      ('Morgen', Icons.wb_twilight, 6, 10),
      ('Dag', Icons.wb_sunny_outlined, 10, 16),
      ('Ettermiddag', Icons.wb_sunny, 16, 20),
      ('Kveld/natt', Icons.nightlight_outlined, 20, 30),
    ];
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Tidslinje', icon: Icons.timeline),
          const SizedBox(height: 8),
          for (final (label, icon, h0, h1) in periods)
            _PeriodRow(
              label: label,
              icon: icon,
              hours: hours
                  .where(
                    (h) => h1 <= 24
                        ? h.time.hour >= h0 && h.time.hour < h1
                        : h.time.hour >= h0 || h.time.hour < h1 - 24,
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<WeatherHour> hours;
  const _PeriodRow({
    required this.label,
    required this.icon,
    required this.hours,
  });

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 16, color: NkColors.textSecondary),
            const SizedBox(width: 10),
            Text(
              '$label: ',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              'ingen data i perioden',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final temps = hours.map((h) => h.temperature).whereType<double>();
    final wind = hours.map((h) => h.windSpeed).whereType<double>();
    final feels = hours.map((h) => h.feelsLike).whereType<double>();
    final tempMin = temps.isEmpty
        ? null
        : temps.reduce((a, b) => a < b ? a : b);
    final feelsMin = feels.isEmpty
        ? null
        : feels.reduce((a, b) => a < b ? a : b);
    final precip = hours
        .map((h) => h.precipitationMm)
        .whereType<double>()
        .fold(0.0, (a, b) => a + b);
    final symbol = hours[(hours.length / 2).floor()].symbolCode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NkColors.primaryBlue),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (temps.isNotEmpty)
                  Text(
                    '${fmtTemp(temps.reduce((a, b) => a < b ? a : b))} – ${fmtTemp(temps.reduce((a, b) => a > b ? a : b))}',
                    style: const TextStyle(fontSize: 12),
                  ),
                // Wind chill is what decides whether you freeze on the
                // summit — shown only when it differs noticeably.
                if (tempMin != null &&
                    feelsMin != null &&
                    feelsMin < tempMin - 1.5)
                  Text(
                    'føles som ${fmtTemp(feelsMin)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: NkColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (precip > 0.05)
                  Text(
                    fmtPrecip(precip),
                    style: const TextStyle(
                      fontSize: 12,
                      color: NkColors.primaryBlue,
                    ),
                  ),
                if (wind.isNotEmpty)
                  Text(
                    fmtWind(wind.reduce((a, b) => a > b ? a : b)),
                    style: const TextStyle(fontSize: 12),
                  ),
                if (symbol != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MetSymbolIcon(symbol, size: 22),
                      const SizedBox(width: 4),
                      Text(
                        symbolLabel(symbol),
                        style: TextStyle(
                          fontSize: 10,
                          color: NkColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
