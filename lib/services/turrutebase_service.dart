import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../core/geo.dart';
import '../models/route_models.dart';
import '../models/trip.dart';
import 'weather_service.dart' show ServiceException, describeNetworkError;

/// Route categories in Kartverket's Turrutebase (WFS feature types).
enum TrailType { foot, ski, bike, other }

/// One mapped trail/track from Turrutebasen — a real, registered
/// route (not an estimate), maintained by a named authority.
class TrailRoute {
  final String id;
  final String name;
  final TrailType type;
  final List<RoutePoint> points;
  final String number;
  final String maintainer;
  final String grading;
  double distanceMeters;

  TrailRoute({
    required this.id,
    required this.type,
    required this.points,
    this.name = '',
    this.number = '',
    this.maintainer = '',
    this.grading = '',
    this.distanceMeters = 0,
  });

  LatLng? get start => points.isEmpty ? null : points.first.latLng;

  /// Trail geometry does not change after parsing. Reuse map coordinates
  /// across camera/panel rebuilds instead of allocating them each time.
  late final List<LatLng> latLngs =
      List.unmodifiable(points.map((point) => point.latLng));

  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        [
          name,
          maintainer,
          typeLabel,
          number,
        ].any((value) => value.toLowerCase().contains(q));
  }

  String get typeLabel => switch (type) {
    TrailType.foot => 'Fotrute',
    TrailType.ski => 'Skiløype',
    TrailType.bike => 'Sykkelrute',
    TrailType.other => 'Annen rute',
  };
}

/// Kartverket Turrutebasen — official Norwegian trail database
/// (foot routes, ski tracks, bike routes). WFS 2.0 returns GML only;
/// there is no GeoJSON output on this service. Data © Kartverket,
/// NLOD — attribution required.
class TurrutebaseService {
  static const _endpoint =
      'https://wfs.geonorge.no/skwms1/wfs.turogfriluftsruter';

  static const _typeNames = {
    TrailType.foot: 'Fotrute',
    TrailType.ski: 'Skiløype',
    TrailType.bike: 'Sykkelrute',
    TrailType.other: 'AnnenRute',
  };

  /// Route types typical for the season — used to *highlight* the
  /// right tracks on the map and to pick the default season when a
  /// trail becomes a trip. The fetch itself always asks for every
  /// type: Turrutebasen's coverage is patchy, and a winter view
  /// filtered to ski tracks alone would hide all registered foot
  /// routes in areas without groomed tracks. When a trip [season] is
  /// set it wins; otherwise the calendar decides: November–April is
  /// ski season, May–October is foot/bike season.
  static Set<TrailType> seasonalTypes(DateTime now, TripSeason? season) {
    if (season != null) {
      return season == TripSeason.winter
          ? {TrailType.ski}
          : {TrailType.foot, TrailType.bike};
    }
    final m = now.month;
    return (m >= 11 || m <= 4)
        ? {TrailType.ski}
        : {TrailType.foot, TrailType.bike};
  }

  /// Maps the calendar to an app season for trips created from a
  /// trail: Mar–May spring, Jun–Aug summer, Sep–Oct autumn, else
  /// winter.
  static TripSeason seasonForDate(DateTime d) => switch (d.month) {
    3 || 4 || 5 => TripSeason.spring,
    6 || 7 || 8 => TripSeason.summer,
    9 || 10 => TripSeason.autumn,
    _ => TripSeason.winter,
  };

  /// Fetches trails intersecting the bbox (south, west, north, east)
  /// for the given [types]. Returns an empty list on empty responses;
  /// network and HTTP failures throw [ServiceException].
  Future<List<TrailRoute>> fetchInBounds(
    double south,
    double west,
    double north,
    double east,
    Set<TrailType> types,
  ) async {
    if (types.isEmpty) return const [];
    final typenames = types.map((t) => _typeNames[t]!).join(',');
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'service': 'WFS',
        'version': '2.0.0',
        'request': 'GetFeature',
        'typenames': typenames,
        'count': '400',
        // bbox axis order follows the advertised crs — lon,lat here.
        'bbox': '$west,$south,$east,$north,EPSG:4326',
      },
    );

    http.Response res;
    try {
      res = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'NorgesKompasset/1.0 (ai.norgeskompasset.app)',
            },
          )
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw ServiceException(
        'Fikk ikke hentet turruter (${describeNetworkError(e)}).',
      );
    }
    if (res.statusCode != 200) {
      throw ServiceException(
        'Turrutebasen svarte med feil (HTTP ${res.statusCode}).',
      );
    }
    return parse(res.body);
  }

  /// GML → [TrailRoute]s. One feature per `wfs:member` (WFS 2.x) or
  /// `gml:featureMember` (WFS 1.x); geometry is `gml:posList` inside
  /// `senterlinje` in EPSG:4258 (lat,lon order).
  static List<TrailRoute> parse(String body) {
    final doc = XmlDocument.parse(body);
    final out = <TrailRoute>[];
    final members = <XmlElement>[
      ...doc.findAllElements('member', namespaceUri: '*'),
      ...doc.findAllElements('featureMember', namespaceUri: '*'),
    ];
    for (final member in members) {
      for (final feature in member.childElements) {
        final type = switch (feature.name.local) {
          'Fotrute' => TrailType.foot,
          'Skiløype' => TrailType.ski,
          'Sykkelrute' => TrailType.bike,
          'AnnenRute' => TrailType.other,
          _ => null,
        };
        if (type == null) continue;

        // A route can be a MultiLineString — use the longest part.
        List<RoutePoint> best = const [];
        for (final pl in feature.findAllElements(
          'posList',
          namespaceUri: '*',
        )) {
          final nums = pl.innerText
              .trim()
              .split(RegExp(r'\s+'))
              .map(num.tryParse)
              .whereType<num>()
              .toList();
          if (nums.length < 4) continue;
          final pts = <RoutePoint>[
            for (var i = 0; i + 1 < nums.length; i += 2)
              RoutePoint(nums[i].toDouble(), nums[i + 1].toDouble()),
          ];
          if (pts.length > best.length) best = pts;
        }
        if (best.length < 2) continue;

        String text(String local) =>
            feature
                .findAllElements(local, namespaceUri: '*')
                .firstOrNull
                ?.innerText
                .trim() ??
            '';

        out.add(
          TrailRoute(
            id:
                feature.getAttribute('gml:id') ??
                feature.getAttribute('id', namespaceUri: '*') ??
                '${type.name}-${out.length}',
            type: type,
            points: best,
            name: text('rutenavn'),
            number: text('rutenummer'),
            maintainer: text('vedlikeholdsansvarlig'),
            grading: text('gradering'),
            distanceMeters: routeDistanceMeters(best),
          ),
        );
      }
    }
    return out;
  }
}
