import '../models/trip.dart';

class MapDisplaySettings {
  static const kartverket =
      'https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png';
  static const openTopo = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
  static const osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const snow = 'https://tiles.opensnowmap.org/pistes/{z}/{x}/{y}.png';

  String? baseOverride;
  bool? skiOverride;

  bool get automatic => baseOverride == null && skiOverride == null;

  String baseForZoom(double zoom) =>
      baseOverride ?? (zoom < 6 ? osm : kartverket);

  /// Human-readable name of the base map actually in use — shown in
  /// the layer menu so the automatic choice is visible, not hidden.
  String activeBaseLabel(double zoom) => switch (baseForZoom(zoom)) {
    kartverket => 'Kartverket topo',
    openTopo => 'OpenTopoMap',
    _ => 'OpenStreetMap',
  };

  bool skiFor(TripActivity? activity) =>
      skiOverride ?? activity == TripActivity.ski;

  void reset() {
    baseOverride = null;
    skiOverride = null;
  }
}
