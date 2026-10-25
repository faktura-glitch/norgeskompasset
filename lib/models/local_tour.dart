import '../core/geo.dart';
import 'route_models.dart';
import 'trip.dart';

typedef TourStop = ({String name, double lat, double lon});

class LocalTour {
  final String id;
  final String name;
  final String municipality;
  final String region;
  final TripActivity activity;
  final CarryMode carry;
  final TripSeason season;
  final List<int> months;
  final int durationDays;
  final AccommodationType accommodation;
  final double reportedDistanceKm;
  final double? reportedElevationGainMeters;
  final String description;
  final String warning;
  final List<TourStop> stops;
  final bool returnSameWay;
  final String provenance;

  const LocalTour({
    required this.id,
    required this.name,
    required this.municipality,
    required this.region,
    required this.activity,
    this.carry = CarryMode.backpack,
    required this.season,
    required this.months,
    required this.durationDays,
    required this.accommodation,
    required this.reportedDistanceKm,
    this.reportedElevationGainMeters,
    required this.description,
    required this.warning,
    required this.stops,
    this.returnSameWay = false,
    this.provenance = userProvidedProvenance,
  });

  static const userProvidedProvenance =
      'Brukerlevert planmal – ikke kontrollert';
  static const curatedProvenance =
      'Kurert planmal (NorgesKompasset) – ikke kontrollert';
  static const limitations =
      'Koordinater, lengde, stigning og sesong er samlet uten full '
      'verifisering. Linjen forbinder noen få punkter, ikke et komplett '
      'rutespor. Ikke bruk den som navigasjonsgrunnlag. Pakkeliste og matplan '
      'er foreløpige uten ferskt vær eller kontrollert terrengprofil.';

  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        [
          name,
          municipality,
          region,
          description,
          activity.label,
        ].any((value) => value.toLowerCase().contains(q));
  }

  HikingRoute previewRoute() {
    final ordered = [...stops, if (returnSameWay) ...stops.reversed.skip(1)];
    final points = [for (final stop in ordered) RoutePoint(stop.lat, stop.lon)];
    return HikingRoute(
      points: points,
      waypoints: [
        for (var i = 0; i < ordered.length; i++)
          Waypoint(
            id: '$id-$i',
            name: ordered[i].name,
            lat: ordered[i].lat,
            lon: ordered[i].lon,
            type: i == 0
                ? WaypointType.start
                : i == ordered.length - 1
                ? WaypointType.end
                : WaypointType.waypoint,
          ),
      ],
      source: RouteSource.estimated,
      distanceMeters: routeDistanceMeters(points),
    );
  }

  Trip createDraft({
    required String tripId,
    required DateTime startDate,
    required int days,
    required int participants,
    required AccommodationType accommodation,
  }) {
    if (days < 1 || days > 14 || participants < 1 || participants > 50) {
      throw ArgumentError('Ugyldig varighet eller deltakerantall.');
    }
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    return Trip(
      id: tripId,
      name: name,
      localTourId: id,
      activity: activity,
      carry: carry,
      season: season,
      accommodation: accommodation,
      startDate: start,
      endDate: start.add(Duration(days: days - 1)),
      participants: participants,
      route: previewRoute(),
      notes:
          '$provenance ($id).\n$LocalTour.limitations\n$description\n$warning\n'
          'Oppgitt lengde: $reportedDistanceKm km. '
          'Oppgitt stigning: ${reportedElevationGainMeters == null ? 'ukjent' : '${reportedElevationGainMeters!.round()} m'}. '
          'Disse tallene er ikke lagt inn som målte rutestatistikker. '
          'Varighet $days dager er et planvalg, ikke en kontrollert etappeplan.\n'
          'Kommune: $municipality. Område: $region.',
    );
  }
}
