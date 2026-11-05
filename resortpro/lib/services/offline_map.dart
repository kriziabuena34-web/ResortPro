import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userAgent = 'com.example.resortpro (ResortPro capstone app)';

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
