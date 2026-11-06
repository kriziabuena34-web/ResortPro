import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userAgent = 'com.aryana.resortpro (ResortPro capstone app)';

// ===========================================================================
// 1) OFFLINE NA MAPA
// Bawat bahagi ng mapa (tile) na nakita na ay sine-save sa phone.
// Kapag walang internet, iyon ang ipapakita.
// ===========================================================================

class OfflineTileProvider extends TileProvider {
  OfflineTileProvider() : super(headers: {'User-Agent': _userAgent});

  /// Gaano katagal bago i-refresh ang naka-save na tile (kapag may internet).
  static const refreshAfter = Duration(days: 30);

  static Directory? _dir;

  static Future<Directory> cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/map_tiles');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Laki ng naka-save na mapa (para maipakita sa user).
  static Future<int> cacheSizeBytes() async {
    try {
      final dir = await cacheDir();
      var total = 0;
      await for (final f in dir.list(recursive: true)) {
        if (f is File) total += await f.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      url: getTileUrl(coordinates, options),
      relativePath: '${coordinates.z}/${coordinates.x}/${coordinates.y}.png',
      headers: headers,
    );
  }
}

// ===========================================================================
// 1b) I-SAVE ANG MAPA PARA SA OFFLINE
// Dina-download nang maaga ang paligid ng resort at ang daan papunta roon,
// para may mapa kahit unang beses buksan nang walang internet.
// Maliit lang (ilang daang tile), para sumunod sa patakaran ng OpenStreetMap.
// ===========================================================================

class OfflineMapSaver {
  OfflineMapSaver._();

  static const _tileUrl = 'https://tile.openstreetmap.org';
  static const _savedKey = 'offline_map_saved_at';
  static bool _running = false;

  static bool get isRunning => _running;

  /// Kailan huling na-save ang offline na mapa (null kung hindi pa).
  static Future<DateTime?> savedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// May internet ba ngayon? (mabilis na tingin lang)
  static Future<bool> isOnline() async {
    try {
      final r = await InternetAddress.lookup('tile.openstreetmap.org').timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static int _x(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
  static int _y(double lat, int z) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor();
  }

  /// Mga tile sa paligid ng [center] na may layong [radiusKm], mula zoom [minZ] hanggang [maxZ].
  static Iterable<TileCoordinates> _area(LatLng center, double radiusKm, int minZ, int maxZ) sync* {
    final dLat = radiusKm / 111.0;
    final dLon = radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180));
    for (var z = minZ; z <= maxZ; z++) {
      final x0 = _x(center.longitude - dLon, z), x1 = _x(center.longitude + dLon, z);
      final y0 = _y(center.latitude + dLat, z), y1 = _y(center.latitude - dLat, z);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          yield TileCoordinates(x, y, z);
        }
      }
    }
  }

  /// Mga tile na dinadaanan ng ruta (zoom 11–15).
  static Iterable<TileCoordinates> _corridor(List<LatLng> points) sync* {
    for (var z = 11; z <= 15; z++) {
      for (final p in points) {
        yield TileCoordinates(_x(p.longitude, z), _y(p.latitude, z), z);
      }
    }
  }

  /// I-download ang mga tile na wala pa sa phone. Ibinabalik kung ilan ang na-save.
  static Future<int> save({
    required LatLng resort,
    LatLng? me,
    List<LatLng> route = const [],
    void Function(int done, int total)? onProgress,
  }) async {
    if (_running) return 0;
    _running = true;
    try {
      final tiles = <String, TileCoordinates>{};
      void addAll(Iterable<TileCoordinates> list) {
        for (final t in list) {
          tiles['${t.z}/${t.x}/${t.y}'] = t;
        }
      }

      addAll(_area(resort, 1.5, 12, 17)); // paligid ng resort, malinaw na detalye
      addAll(_area(resort, 6, 12, 14)); // bayan ng Pagsanjan at karatig
      if (me != null) addAll(_area(me, 0.8, 13, 16)); // kung nasaan ka ngayon
      if (route.isNotEmpty) addAll(_corridor(route)); // daan papunta sa resort

      final dir = await OfflineTileProvider.cacheDir();
      final keys = tiles.keys.toList();
      var done = 0, saved = 0;
      final client = http.Client();
      try {
        // Dalawang sabay lang para hindi mabigatan ang server ng OpenStreetMap.
        Future<void> worker(int start) async {
          for (var i = start; i < keys.length; i += 2) {
            final file = File('${dir.path}/${keys[i]}.png');
            if (!await file.exists()) {
              try {
                final res = await client
                    .get(Uri.parse('$_tileUrl/${keys[i]}.png'), headers: {'User-Agent': _userAgent})
                    .timeout(const Duration(seconds: 10));
                if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(res.bodyBytes, flush: true);
                  saved++;
                }
              } catch (_) {}
            }
            done++;
            onProgress?.call(done, keys.length);
          }
        }

        await Future.wait([worker(0), worker(1)]);
      } finally {
        client.close();
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_savedKey, DateTime.now().toIso8601String());
      } catch (_) {}
      return saved;
    } finally {
      _running = false;
    }
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({required this.url, required this.relativePath, required this.headers});

  final String url;
  final String relativePath;
  final Map<String, String> headers;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_CachedTileImage>(this);

  @override
  ImageStreamCompleter loadImage(_CachedTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final dir = await OfflineTileProvider.cacheDir();
    final file = File('${dir.path}/$relativePath');
    final exists = await file.exists();

    // Sariwa pa ang naka-save: hindi na kailangan ng internet.
    if (exists) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age < OfflineTileProvider.refreshAfter) {
        return decode(await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));
      }
    }

    try {
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return await decode(await ui.ImmutableBuffer.fromUint8List(res.bodyBytes));
      }
      throw Exception('Tile HTTP ${res.statusCode}');
    } catch (e) {
      // Walang internet: gamitin ang luma kung meron.
      if (exists) {
        return decode(await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));
      }
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is _CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

// ===========================================================================
// 2) TOTOONG RUTA SA KALSADA (OSRM, libre)
// Naka-save din ang huling ruta para makita kahit offline.
// ===========================================================================

class RoadRoute {
  RoadRoute({
    required this.points,
    required this.meters,
    required this.seconds,
    required this.from,
    required this.fetchedAt,
    this.fromCache = false,
  });

  final List<LatLng> points;
  final double meters;
  final double seconds;
  final LatLng from;
  final DateTime fetchedAt;
  final bool fromCache;

  Map<String, dynamic> toJson() => {
        'points': [for (final p in points) [p.latitude, p.longitude]],
        'meters': meters,
        'seconds': seconds,
        'from': [from.latitude, from.longitude],
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  static RoadRoute fromJson(Map<String, dynamic> j, {bool fromCache = false}) => RoadRoute(
        points: [
          for (final p in (j['points'] as List)) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        meters: (j['meters'] as num).toDouble(),
        seconds: (j['seconds'] as num).toDouble(),
        from: LatLng((j['from'][0] as num).toDouble(), (j['from'][1] as num).toDouble()),
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        fromCache: fromCache,
      );
}

class RouteService {
  static const _prefsKey = 'resort_last_route';
  static const _distance = Distance();

  /// Kunin ang ruta mula [from] papunta [to]. Kapag walang internet,
  /// ibabalik ang huling naka-save na ruta (kung malapit pa rin sa kinaroroonan).
  static Future<RoadRoute?> fetch(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(uri, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('Route HTTP ${res.statusCode}');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List? ?? const [];
      if (routes.isEmpty) throw Exception('No route found');
      final r = routes.first as Map<String, dynamic>;
      final coords = (r['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final route = RoadRoute(
        points: coords,
        meters: (r['distance'] as num).toDouble(),
        seconds: (r['duration'] as num).toDouble(),
        from: from,
        fetchedAt: DateTime.now(),
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(route.toJson()));
      } catch (_) {}
      return route;
    } catch (_) {
      return loadSaved(near: from);
    }
  }

  /// Ang huling naka-save na ruta (para sa offline).
  static Future<RoadRoute?> loadSaved({LatLng? near}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final route = RoadRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>, fromCache: true);
      // Kung napakalayo na sa pinanggalingan ng naka-save na ruta, hindi na ito tugma.
      if (near != null && _distance.as(LengthUnit.Kilometer, near, route.from) > 5) return null;
      return route;
    } catch (_) {
      return null;
    }
  }

  /// Gaano kalayo pa sa daan (mula sa puntong pinakamalapit sa [me] hanggang dulo).
  static double remainingMeters(RoadRoute route, LatLng me) {
    if (route.points.length < 2) return route.meters;
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < route.points.length; i++) {
      final d = _distance.as(LengthUnit.Meter, me, route.points[i]);
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    var total = 0.0;
    for (var i = nearest; i < route.points.length - 1; i++) {
      total += _distance.as(LengthUnit.Meter, route.points[i], route.points[i + 1]);
    }
    return total;
  }
}
