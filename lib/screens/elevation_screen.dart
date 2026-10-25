import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/tile_cache.dart';
import '../widgets/app_shell.dart';

import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'map_planner_screen.dart';

class ElevationScreen extends StatelessWidget {
  const ElevationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    return Scaffold(
      appBar: AppBar(
        title: tripScreenTitle('Høydeprofil og etapper', trip),
        actions: [
          if (trip?.route?.hasRoute == true)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Vis på kart',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapPlannerScreen()),
              ),
            ),
        ],
      ),
      body: trip == null || trip.route?.hasRoute != true
          ? const EmptyState(
              icon: Icons.terrain,
              title: 'Ingen rute å analysere',
              message: 'Planlegg en rute i kartet først – da får du høydeprofil, etapper og vanskelighetsanalyse her.',
            )
          : _AnalysisBody(trip: trip, wide: wide),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  final Trip trip;
  final bool wide;
  const _AnalysisBody({required this.trip, required this.wide});

  @override
  Widget build(BuildContext context) {
    final route = trip.route!;
    final hasElevation = route.points.any((p) => p.elevation != null);

    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        _OverallStats(trip: trip),
        const SizedBox(height: 8),
        Text(
          '${trip.activity.label} · tid er et estimat; legg til pauser og margin for forholdene.',
        ),
        const SizedBox(height: 12),
        SectionHeader(
          trip.name.isEmpty ? 'Turanalyse' : trip.name,
          icon: Icons.insights,
          trailing: TextButton.icon(
            onPressed: () => context.read<AppState>().fetchElevation(trip),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Oppdater høyder'),
          ),
        ),
        const SizedBox(height: 12),
        if (!hasElevation)
          NkCard(
            color: NkColors.warningAmber.withValues(alpha: 0.08),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: NkColors.warningAmber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Høydedata er ikke hentet ennå. Trykk «Oppdater høyder» for å beregne profil, stigning og etappeanalyse.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          NkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader('Høydeprofil', icon: Icons.show_chart),
                const SizedBox(height: 6),
                Text(
                  'Distanse i km mot moh. Etappegrenser er markert.'
                  '${route.straightRanges.isNotEmpty ? ' Gulllige felt = estimert rett strekk (ikke sti).' : ''}',
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: wide ? 260 : 200,
                  child: ElevationChart(
                    points: route.points,
                    stageBoundaries: _stageBoundaries(),
                    straightKm: _straightKmRanges(route),
                    // Tap a point in the profile → open the map
                    // centered on that exact route position.
                    onTapPoint: (ll) => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => SafeArea(
                        child: SizedBox(
                          height: 340,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: ll,
                              initialZoom: 13,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: TileCache.urlTemplate,
                                tileProvider: PersistentTileProvider(),
                                userAgentPackageName: 'ai.norgeskompasset.app',
                              ),
                              PolylineLayer(polylines: routePolylines(route)),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: ll,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: NkColors.dangerRed,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trykk i profilen for å se punktet på kartet',
                  style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const SectionHeader('Etapper', icon: Icons.flag_outlined),
        const SizedBox(height: 10),
        if (trip.stages.isEmpty)
          NkCard(
            child: Column(
              children: [
                const Text(
                  'Ingen etapper ennå. Del ruten inn i passe dagsetapper.',
                ),
                TextButton(
                  onPressed: () {
                    context.read<NavController>().goTo(2);
                    Navigator.pop(context);
                  },
                  child: const Text('Åpne etappeplanlegging'),
                ),
              ],
            ),
          )
        else
          for (final stage in trip.stages) ...[
            _StageCard(stage: stage, trip: trip),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 8),
        NkCard(
          padding: EdgeInsets.all(12),
          child: Text(
            'Merk: vurderingene er veiledende og basert på distanse, stigning og terrengdata – ikke en garanti for sikkerhet. Bruk alltid eget skjønn og sjekk forholdene.',
            style: TextStyle(
              fontSize: 11,
              color: NkColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  List<double> _stageBoundaries() {
    // Cumulative km where each stage ends (excluding the last).
    final out = <double>[];
    var acc = 0.0;
    for (var i = 0; i < trip.stages.length - 1; i++) {
      acc += trip.stages[i].distanceMeters / 1000;
      out.add(acc);
    }
    return out;
  }

  /// Km-positions of straight-line (estimated) stretches, so the
  /// profile shades them instead of presenting them as trail data.
  List<(double, double)> _straightKmRanges(HikingRoute route) {
    if (route.straightRanges.isEmpty) return const [];
    final cum = cumulativeDistances(route.points);
    final last = route.points.length - 1;
    return [
      for (final r in route.straightRanges)
        (cum[r.start.clamp(0, last)] / 1000, cum[r.end.clamp(0, last)] / 1000),
    ];
  }
}

/// Interactive elevation line chart. Tapping/dragging shows the
/// distance, altitude and stage at that position.
class ElevationChart extends StatefulWidget {
  final List<RoutePoint> points;
  final List<double> stageBoundaries; // km
  final List<(double, double)> straightKm; // km ranges, estimated
  final double height;

  /// Called when the user taps (not drags) a point in the profile —
  /// receives the route position, e.g. to show it on the map.
  final ValueChanged<LatLng>? onTapPoint;

  const ElevationChart({
    super.key,
    required this.points,
    this.stageBoundaries = const [],
    this.straightKm = const [],
    this.height = 200,
    this.onTapPoint,
  });

  @override
  State<ElevationChart> createState() => _ElevationChartState();
}

class _ElevationChartState extends State<ElevationChart> {
  int? _touchedIndex;

  // Chart geometry is computed once per point set — rebuilding on
  // touch events must not rerun the distance/elevation scans.
  List<RoutePoint> _pts = const [];
  List<double> _cum = const [];
  double _minE = 0, _maxE = 0;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(ElevationChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) _compute();
  }

  void _compute() {
    _pts = widget.points.where((p) => p.elevation != null).toList();
    if (_pts.length < 2) {
      _cum = const [];
      return;
    }
    _cum = cumulativeDistances(_pts);
    _minE = _maxE = _pts.first.elevation!;
    for (final p in _pts) {
      if (p.elevation! < _minE) _minE = p.elevation!;
      if (p.elevation! > _maxE) _maxE = p.elevation!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = _pts;
    if (pts.length < 2) {
      return Center(
        child: Text(
          'For få høydepunkter til å tegne profilen',
          style: TextStyle(color: NkColors.textSecondary),
        ),
      );
    }
    final cum = _cum;
    final totalKm = cum.last / 1000;
    final minE = _minE, maxE = _maxE;
    final pad = (maxE - minE).clamp(20, double.infinity) * 0.1;

    return LineChart(
      LineChartData(
        minY: minE - pad,
        maxY: maxE + pad,
        minX: 0,
        maxX: totalKm,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((maxE - minE) / 4).clamp(1, double.infinity),
          getDrawingHorizontalLine: (_) =>
              FlLine(color: NkColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: [
            for (final (s, e) in widget.straightKm)
              VerticalRangeAnnotation(
                x1: s,
                x2: e,
                color: NkColors.warningAmber.withValues(alpha: 0.10),
              ),
          ],
        ),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            for (final km in widget.stageBoundaries)
              VerticalLine(
                x: km,
                color: NkColors.warningAmber.withValues(alpha: 0.6),
                strokeWidth: 1.5,
                dashArray: [5, 4],
              ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (totalKm / 5).clamp(0.5, double.infinity),
              reservedSize: 30,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)} km',
                style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: ((maxE - minE) / 4).clamp(1, double.infinity),
              reservedSize: 52,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)} m',
                style: TextStyle(fontSize: 10, color: NkColors.textSecondary),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            final spot = response?.lineBarSpots?.firstOrNull;
            setState(() {
              _touchedIndex = spot?.spotIndex;
            });
            if (event is FlTapUpEvent && spot != null) {
              final p = _pts[spot.spotIndex];
              widget.onTapPoint?.call(p.latLng);
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => NkColors.primaryBlue,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.y.toStringAsFixed(0)} moh\n${s.x.toStringAsFixed(1)} km',
                  const TextStyle(color: Colors.white, fontSize: 11),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < pts.length; i++)
                FlSpot(cum[i] / 1000, pts[i].elevation!),
            ],
            isCurved: true,
            curveSmoothness: 0.15,
            color: NkColors.primaryBlue,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  NkColors.primaryBlue.withValues(alpha: 0.28),
                  NkColors.primaryBlue.withValues(alpha: 0.02),
                ],
              ),
            ),
            showingIndicators: _touchedIndex != null ? [_touchedIndex!] : [],
          ),
        ],
      ),
    );
  }
}

class _OverallStats extends StatelessWidget {
  final Trip trip;
  const _OverallStats({required this.trip});

  @override
  Widget build(BuildContext context) {
    final route = trip.route!;
    final totalTime = trip.totalEstimatedMinutes;
    final hardest = trip.stages.isEmpty
        ? null
        : trip.stages.reduce(
            (a, b) => (a.difficulty?.score ?? 0) >= (b.difficulty?.score ?? 0)
                ? a
                : b,
          );
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Totalt for turen',
            icon: Icons.summarize_outlined,
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: context.isWide ? 6 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.1,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              InfoTile(
                'Distanse',
                fmtKm(route.distanceMeters),
                icon: Icons.route,
              ),
              InfoTile(
                'Stigning',
                '+${route.totalAscent.round()} m',
                icon: Icons.trending_up,
              ),
              InfoTile(
                'Nedstigning',
                '−${route.totalDescent.round()} m',
                icon: Icons.trending_down,
              ),
              InfoTile(
                'Høyeste punkt',
                fmtMeters(route.highestPoint),
                icon: Icons.terrain,
              ),
              InfoTile(
                'Estimert tid',
                totalTime > 0 ? fmtDuration(totalTime) : '–',
                icon: Icons.schedule,
              ),
              InfoTile(
                'Vanskeligste etappe',
                hardest == null ? '–' : 'Etappe ${hardest.number}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final Stage stage;
  final Trip trip;
  const _StageCard({required this.stage, required this.trip});

  @override
  Widget build(BuildContext context) {
    final d = stage.difficulty;
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Etappe ${stage.number} – ${fmtDate(stage.date)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (d != null)
                StatusPill(d.level.label, difficultyColor(d.level)),
            ],
          ),
          Text(
            '${stage.startName} → ${stage.endName}',
            style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        InfoTile('Distanse', fmtKm(stage.distanceMeters)),
                        InfoTile('Stigning', '+${stage.ascent.round()} m'),
                        InfoTile('Ned', '-${stage.descent.round()} m'),
                        InfoTile('Tid', fmtDuration(stage.estimatedMinutes)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                height: 44,
                child: _MiniProfile(points: stage.points),
              ),
            ],
          ),
          if (stage.challenges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in stage.challenges)
                  StatusPill(c, NkColors.primaryBlue, icon: Icons.info_outline),
              ],
            ),
          ],
          if (d != null && d.score >= 45) ...[
            const SizedBox(height: 8),
            Text(
              'Etappe ${stage.number} kan være krevende: ${d.factors.join("; ").toLowerCase()}.',
              style: TextStyle(fontSize: 12, color: NkColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniProfile extends StatelessWidget {
  final List<RoutePoint> points;
  const _MiniProfile({required this.points});

  @override
  Widget build(BuildContext context) {
    final pts = points.where((p) => p.elevation != null).toList();
    if (pts.length < 2) {
      return Center(
        child: Icon(Icons.show_chart, color: NkColors.border, size: 28),
      );
    }
    var minE = pts.first.elevation!, maxE = pts.first.elevation!;
    for (final p in pts) {
      if (p.elevation! < minE) minE = p.elevation!;
      if (p.elevation! > maxE) maxE = p.elevation!;
    }
    final cum = cumulativeDistances(pts);
    return LineChart(
      LineChartData(
        minY: minE - 1,
        maxY: maxE + 1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < pts.length; i++)
                FlSpot(cum[i], pts[i].elevation!),
            ],
            isCurved: true,
            curveSmoothness: 0.2,
            color: NkColors.forestGreen,
            barWidth: 1.8,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: NkColors.forestGreen.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
