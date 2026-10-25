import 'dart:io';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart' as xml;
import '../models/route_models.dart';
import '../models/trip.dart';
import 'weather_service.dart' show ServiceException;

/// Exports a trip's route as GPX 1.1 — a standard format understood by
/// UT.no, Garmin, Strava and other tools.
class GpxService {
  /// Builds the GPX XML document. Waypoints become `wpt`, the route a
  /// single `trk`/`trkseg`. Elevations are included when present.
  static String toGpx(Trip trip) {
    final route = trip.route;
    final name = trip.name.isEmpty ? 'NorgesKompasset tur' : trip.name;
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="NorgesKompasset" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <metadata>')
      ..writeln('    <name>${esc(name)}</name>')
      ..writeln('    <time>${DateTime.now().toUtc().toIso8601String()}</time>')
      ..writeln('  </metadata>');

    for (final w in route?.waypoints ?? const <Waypoint>[]) {
      b.writeln(
          '  <wpt lat="${w.lat.toStringAsFixed(6)}" lon="${w.lon.toStringAsFixed(6)}">'
          '<name>${esc(w.name)}</name><type>${w.type.name}</type></wpt>');
    }

    if (route != null && route.points.isNotEmpty) {
      b.writeln('  <trk><name>${esc(name)}</name><trkseg>');
      for (final p in route.points) {
        b.write(
            '    <trkpt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lon.toStringAsFixed(6)}">');
        if (p.elevation != null) {
          b.write('<ele>${p.elevation!.toStringAsFixed(1)}</ele>');
        }
        b.writeln('</trkpt>');
      }
      b.writeln('  </trkseg></trk>');
    }
    b.writeln('</gpx>');
    return b.toString();
  }

  static String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Exports the recorded track log as GPX 1.1 with timestamps —
  /// this is what you actually walked, distinct from the plan.
  /// Returns null when no track has been recorded.
  static String? trackToGpx(Trip trip) {
    if (trip.trackLog.length < 2) return null;
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="NorgesKompasset" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <trk><name>${esc(trip.name.isEmpty ? 'Gått rute' : '${trip.name} (spor)')}</name>'
          '<trkseg>');
    for (final t in trip.trackLog) {
      b.write('    <trkpt lat="${t.lat.toStringAsFixed(6)}" '
          'lon="${t.lon.toStringAsFixed(6)}">');
      if (t.elevation != null) {
        b.write('<ele>${t.elevation}</ele>');
      }
      b.write('<time>${t.time.toUtc().toIso8601String()}</time>');
      b.writeln('</trkpt>');
    }
    b.writeln('  </trkseg></trk>');
    b.write('</gpx>');
    return b.toString();
  }

  /// Parses a GPX 1.x document into route points and waypoints.
  /// Track points (`trkpt`) are preferred; route points (`rtept`)
  /// are used when no track exists. Throws [ServiceException] on
  /// documents with no usable route data.
  static ({List<RoutePoint> points, List<Waypoint> waypoints, String? name})
      parse(String gpxText) {
    xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(gpxText);
    } catch (_) {
      throw const ServiceException('Kunne ikke lese GPX-filen (ugyldig XML).');
    }

    final points = <RoutePoint>[];
    for (final trkpt in doc.findAllElements('trkpt')) {
      final lat = double.tryParse(trkpt.getAttribute('lat') ?? '');
      final lon = double.tryParse(trkpt.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      points.add(RoutePoint(lat, lon,
          elevation:
              double.tryParse(trkpt.getElement('ele')?.innerText ?? '')));
    }
    if (points.isEmpty) {
      for (final rtept in doc.findAllElements('rtept')) {
        final lat = double.tryParse(rtept.getAttribute('lat') ?? '');
        final lon = double.tryParse(rtept.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        points.add(RoutePoint(lat, lon,
            elevation:
                double.tryParse(rtept.getElement('ele')?.innerText ?? '')));
      }
    }
    if (points.length < 2) {
      throw const ServiceException(
          'GPX-filen inneholder ingen trasé å importere.');
    }

    final waypoints = <Waypoint>[];
    var i = 0;
    for (final wpt in doc.findAllElements('wpt')) {
      final lat = double.tryParse(wpt.getAttribute('lat') ?? '');
      final lon = double.tryParse(wpt.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      waypoints.add(Waypoint(
        id: 'gpx-w$i',
        name: wpt.getElement('name')?.innerText ?? 'Punkt ${i + 1}',
        lat: lat,
        lon: lon,
        type: WaypointType.waypoint,
      ));
      i++;
    }

    final name = doc
        .findAllElements('trk')
        .firstOrNull
        ?.getElement('name')
        ?.innerText;

    return (points: points, waypoints: waypoints, name: name);
  }

  /// Saves the GPX to the user's Downloads folder (native) — returns
  /// the file path. Not available on web (use share/copy instead).
  static Future<String> exportToDownloads(Trip trip) async {
    if (kIsWeb) {
      throw const ServiceException(
          'Filnedlasting støttes ikke i nettleseren – kopier GPX-teksten i stedet.');
    }
    final route = trip.route;
    if (route == null || !route.hasRoute) {
      throw const ServiceException('Turen har ingen rute å eksportere.');
    }
    return _saveGpx(trip.name.isEmpty ? 'tur' : trip.name, toGpx(trip));
  }

  /// Saves the recorded track log as a GPX file — null/throws when
  /// nothing has been recorded.
  static Future<String> exportTrackToDownloads(Trip trip) async {
    if (kIsWeb) {
      throw const ServiceException(
          'Filnedlasting støttes ikke i nettleseren – kopier GPX-teksten i stedet.');
    }
    final gpx = trackToGpx(trip);
    if (gpx == null) {
      throw const ServiceException(
          'Ingen spor logget ennå – turmodus må ha registrert posisjoner.');
    }
    return _saveGpx(
        '${trip.name.isEmpty ? 'tur' : trip.name}_spor', gpx);
  }

  static Future<String> _saveGpx(String name, String gpx) async {
    final safeName =
        name.replaceAll(RegExp(r'[^\w\-]+'), '_').toLowerCase();
    // Mobile has no public Downloads dir — write to temp and let the
    // OS share sheet deliver it (Files, Drive, e-mail, etc.).
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$safeName.gpx');
      await file.writeAsString(gpx);
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)], text: name));
      return 'Delt via delingsarket (${file.path})';
    }
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$safeName.gpx');
    await file.writeAsString(gpx);
    return file.path;
  }
}
