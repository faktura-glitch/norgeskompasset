import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Persistent map-tile cache backed by Hive. Tiles the user has viewed
/// once are stored locally, so the map still renders for those areas
/// when the device is offline (e.g. active hiking mode in the field).
///
/// Works on all platforms: on desktop/native the box lives on disk, on
/// web it uses IndexedDB. The cache is capped; oldest entries are
/// evicted when the limit is reached.
class TileCache {
  static const _boxName = 'map_tiles';
  static const _maxTiles = 2000;

  static Box<dynamic>? _box;
  static int _revision = 0;
  static int get revision => _revision;

  static Future<void> init() async {
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      _revision++;
    } catch (_) {
      // A locked/corrupt cache file must not take the map down —
      // tiles then just load without persistence until the next
      // successful init (e.g. after the lock holder exits).
      _box = null;
    }
  }

  /// The box when it is actually usable — a killed process can leave
  /// the underlying file closed even though the Box object exists.
  static Box<dynamic>? _open() {
    final b = _box;
    return (b != null && b.isOpen) ? b : null;
  }

  static Uint8List? read(String url) {
    try {
      final v = _open()?.get(url);
      if (v is Uint8List) return v;
      if (v is List) {
        return Uint8List.fromList(v.cast<int>());
      }
    } catch (_) {
      _box = null;
    }
    return null;
  }

  static Future<void> write(String url, Uint8List bytes) async {
    final box = _open();
    if (box == null) return;
    try {
      if (!box.containsKey(url) && box.length >= _maxTiles) {
        await box.deleteAll(box.keys.take(_maxTiles ~/ 4).toList());
      }
      final saved = box.put(url, bytes);
      _revision++;
      await saved;
    } catch (_) {
      // Stop hammering a broken box — the map still renders online.
      _box = null;
    }
  }

  /// Number of tiles currently stored.
  static int get count => _open()?.length ?? 0;

  /// Removes every cached tile (frees disk space).
  static Future<void> clear() async {
    try {
      await _open()?.clear();
    } catch (_) {
      _box = null;
    }
    _revision++;
  }

  static bool isCached(String url) {
    try {
      return _open()?.containsKey(url) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Route pre-download ────────────────────────────────────

  static const urlTemplate =
      'https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png';

  static int _tileX(double lon, int z) =>
      ((lon + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

  static int _tileY(double lat, int z) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
            2 *
            (1 << z))
        .floor()
        .clamp(0, (1 << z) - 1);
  }

  /// Tile URLs covering a padded bounding box around [points], at the
  /// given zoom levels. Low zooms are cheap; high zooms are included
  /// only while the total stays under [cap].
  static List<String> urlsCovering(
    List<LatLng> points, {
    List<int> zooms = const [11, 12, 13, 14],
    int cap = 900,
  }) {
    if (points.isEmpty) return [];
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    // Pad ~15% (min ~2 km) so the route doesn't sit at the edge.
    final padLat = math.max((maxLat - minLat) * 0.15, 0.02);
    final padLon = math.max((maxLon - minLon) * 0.15, 0.03);
    minLat -= padLat;
    maxLat += padLat;
    minLon -= padLon;
    maxLon += padLon;

    final urls = <String>[];
    for (final z in zooms) {
      final level = <String>[];
      for (var x = _tileX(minLon, z); x <= _tileX(maxLon, z); x++) {
        for (var y = _tileY(maxLat, z); y <= _tileY(minLat, z); y++) {
          level.add(
            urlTemplate
                .replaceAll('{z}', '$z')
                .replaceAll('{x}', '$x')
                .replaceAll('{y}', '$y'),
          );
        }
      }
      // Include this zoom level only if it fits under the cap —
      // detail is nice, but a complete low-zoom set beats a partial
      // high-zoom one.
      if (urls.length + level.length > cap) break;
      urls.addAll(level);
    }
    return urls;
  }

  /// Downloads [urls] into the cache, skipping tiles already stored.
  /// Runs a few requests in parallel and reports progress via
  /// [onProgress] (done, total). Returns the number of tiles fetched.
  static Future<int> prefetch(
    List<String> urls, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    final missing = urls.where((u) => !isCached(u)).toList();
    final httpClient = client ?? http.Client();
    var done = urls.length - missing.length;
    var fetched = 0;
    try {
      const batch = 4;
      for (var i = 0; i < missing.length; i += batch) {
        if (isCancelled?.call() == true) break;
        await Future.wait(
          missing.skip(i).take(batch).map((u) async {
            try {
              final res = await httpClient
                  .get(
                    Uri.parse(u),
                    headers: {'User-Agent': 'NorgesKompasset/1.0'},
                  )
                  .timeout(const Duration(seconds: 15));
              if (res.statusCode == 200) {
                await write(u, res.bodyBytes);
                if (isCached(u)) fetched++;
              }
            } catch (_) {
              // A missing tile is not fatal — the user still has the rest.
            }
            done++;
            onProgress?.call(done, urls.length);
          }),
        );
      }
    } finally {
      if (client == null) httpClient.close();
    }
    return fetched;
  }
}

/// A [TileProvider] that reads/writes through [TileCache]. Tiles already
/// in the cache are served without a network call, so the map works
/// offline for previously viewed areas.
class PersistentTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    var url = options.urlTemplate!
        .replaceAll('{z}', '${coordinates.z}')
        .replaceAll('{x}', '${coordinates.x.truncate()}')
        .replaceAll('{y}', '${coordinates.y.truncate()}');
    if (url.contains('{s}')) {
      url = url.replaceAll('{s}', options.subdomains.firstOrNull ?? '');
    }
    return _CachedTileImage(url);
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final String url;
  const _CachedTileImage(this.url);

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      informationCollector: () => [DiagnosticsProperty('url', url)],
    );
  }

  Future<ui.Codec> _load(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) async {
    var bytes = TileCache.read(url);
    final wasCached = bytes != null;
    final fallback = _fallbackUrl(url);
    bytes ??=
        await _fetch(url) ?? (fallback != null ? await _fetch(fallback) : null);
    if (bytes == null) {
      throw Exception('Tile unavailable');
    }
    // Cache under the requested URL so the tile also works offline.
    if (!wasCached) TileCache.write(url, bytes);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  static Future<Uint8List?> _fetch(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'NorgesKompasset/1.0'})
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Kartverket is the slowest source — when it times out, the same
  /// tile from OSM still gives the user a map instead of grey space.
  static String? _fallbackUrl(String url) {
    final re = RegExp(r'cache\.kartverket\.no/.+/(\d+)/(\d+)/(\d+)\.png');
    final m = re.firstMatch(url);
    if (m == null) return null;
    return 'https://tile.openstreetmap.org/'
        '${m.group(1)}/${m.group(3)}/${m.group(2)}.png';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _CachedTileImage && other.url == url);

  @override
  int get hashCode => url.hashCode;
}
