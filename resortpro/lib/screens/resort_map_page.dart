import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/offline_map.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Realtime map: pin ng resort, live na lokasyon mo (blue dot), distansya,
/// at "Get directions" na bubukas sa Google Maps.
class ResortMapPage extends StatefulWidget {
  const ResortMapPage({super.key});

  @override
  State<ResortMapPage> createState() => _ResortMapPageState();
}

class _ResortMapPageState extends State<ResortMapPage> {
  static const _resort = LatLng(resortLatitude, resortLongitude);

  final _map = MapController();
  StreamSubscription<Position>? _positionSub;
  LatLng? _me;
  String? _locationNote; // dahilan kapag walang lokasyon
  bool _followMe = false;

  // Totoong ruta sa kalsada
  final _tiles = OfflineTileProvider();
  RoadRoute? _route;
  bool _routeLoading = false;
  DateTime? _lastRouteTry;

  @override
  void initState() {
    super.initState();
    _startLocation();
    // Ipakita agad ang naka-save na ruta (kahit offline) habang hinahanap ang lokasyon.
    RouteService.loadSaved().then((r) {
      if (mounted && _route == null && r != null) setState(() => _route = r);
    });
  }

  /// Kunin ulit ang ruta kapag: wala pa, lumayo ka ng 150 m sa pinanggalingan,
  /// o naka-save (offline) na ruta pa ang gamit. Hindi lalampas sa isang beses kada 30 segundo.
  Future<void> _maybeRefreshRoute() async {
    final me = _me;
    if (me == null || _routeLoading) return;
    final route = _route;
    final now = DateTime.now();
    if (_lastRouteTry != null && now.difference(_lastRouteTry!) < const Duration(seconds: 30)) return;
    final moved = route == null
        ? double.infinity
        : Geolocator.distanceBetween(me.latitude, me.longitude, route.from.latitude, route.from.longitude);
    if (route != null && !route.fromCache && moved < 150) return;

    _lastRouteTry = now;
    setState(() => _routeLoading = true);
    final fresh = await RouteService.fetch(me, _resort);
    if (!mounted) return;
    setState(() {
      _routeLoading = false;
      if (fresh != null) _route = fresh;
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locationNote = 'Turn on Location to see where you are.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationNote = 'Allow location access to see your distance to the resort.');
        return;
      }

      // Live na lokasyon: nag-a-update habang gumagalaw ka.
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((p) {
        if (!mounted) return;
        final first = _me == null;
        setState(() {
          _me = LatLng(p.latitude, p.longitude);
          _locationNote = null;
        });
        if (first) _fitBoth();
        if (_followMe) _map.move(_me!, _map.camera.zoom);
        _maybeRefreshRoute();
      }, onError: (_) {
        if (mounted) setState(() => _locationNote = 'Could not get your location.');
      });
    } catch (_) {
      if (mounted) setState(() => _locationNote = 'Could not get your location.');
    }
  }

  void _fitBoth() {
    final me = _me;
    if (me == null) {
      _map.move(_resort, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [me, _resort, ...?_route?.points],
        padding: const EdgeInsets.fromLTRB(60, 120, 60, 260),
        maxZoom: 16,
      ),
    );
  }

  double? get _distanceKm => _me == null
      ? null
      : Geolocator.distanceBetween(_me!.latitude, _me!.longitude, resortLatitude, resortLongitude) / 1000;

  Future<void> _openDirections() async {
    final origin = _me == null ? '' : '&origin=${_me!.latitude},${_me!.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1$origin&destination=$resortLatitude,$resortLongitude&travelmode=driving',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final km = _distanceKm;
    final me = _me;
    final route = _route;
    final roadMeters = route == null
        ? null
        : (me == null ? route.meters : RouteService.remainingMeters(route, me));
    // Tantyang oras batay sa natitirang daan.
    final roadMinutes = route == null || roadMeters == null || route.meters <= 0
        ? null
        : (route.seconds * (roadMeters / route.meters) / 60).round();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Resort Map'),
        backgroundColor: Colors.white.withValues(alpha: 0.85),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(
              initialCenter: _resort,
              initialZoom: 15,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.aryana.resortpro',
                // Sine-save ang mapang nakita na, para gumana kahit offline.
                tileProvider: _tiles,
              ),
              if (route != null && route.points.length > 1)
                PolylineLayer(
                  polylines: [
                    // Totoong daan papunta sa resort
                    Polyline(
                      points: route.points,
                      strokeWidth: 6,
                      color: AppColors.primary,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                    // Mula sa kinaroroonan mo hanggang sa simula ng daan
                    if (me != null)
                      Polyline(
                        points: [me, route.points.first],
                        strokeWidth: 3,
                        color: AppColors.primary.withValues(alpha: 0.6),
                        pattern: StrokePattern.dotted(),
                      ),
                  ],
                )
              else if (me != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [me, _resort],
                      strokeWidth: 3,
                      color: AppColors.primary.withValues(alpha: 0.7),
                      pattern: StrokePattern.dashed(segments: const [10, 8]),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _resort,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: const _ResortPin(),
                  ),
                  if (me != null)
                    Marker(
                      point: me,
                      width: 26,
                      height: 26,
                      child: const _MeDot(),
                    ),
                ],
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),

          // Mga floating button sa kanan
          Positioned(
            right: 16,
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
            child: Column(
              children: [
                _RoundButton(
                  icon: Icons.villa_outlined,
                  tooltip: 'Show resort',
                  onTap: () {
                    setState(() => _followMe = false);
                    _map.move(_resort, 16);
                  },
                ),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: _followMe ? Icons.my_location : Icons.location_searching,
                  tooltip: 'My location',
                  active: _followMe,
                  onTap: me == null
                      ? null
                      : () {
                          setState(() => _followMe = !_followMe);
                          if (_followMe) _map.move(me, 16);
                        },
                ),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: Icons.zoom_out_map,
                  tooltip: 'Show both',
                  onTap: () {
                    setState(() => _followMe = false);
                    _fitBoth();
                  },
                ),
              ],
            ),
          ),

          // Glass info card sa ibaba
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: GlassPanel(
              opacity: 0.78,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary]),
                        ),
                        child: const Icon(Icons.beach_access_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Aryana's Guests House",
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            Text(resortAddress, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        km == null ? Icons.location_off_outlined : Icons.near_me_outlined,
                        size: 18,
                        color: km == null ? AppColors.muted : AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              roadMeters != null && me != null
                                  ? '${_formatDistance(roadMeters)} by road'
                                      '${roadMinutes == null ? '' : ' · about ${_formatMinutes(roadMinutes)}'}'
                                  : km == null
                                      ? (_locationNote ?? 'Finding your location…')
                                      : '${_formatDistance(km * 1000)} away (straight line)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: km == null && roadMeters == null ? AppColors.muted : AppColors.text,
                              ),
                            ),
                            if (_routeLoading)
                              const Text('Finding the best road…', style: TextStyle(fontSize: 12, color: AppColors.muted))
                            else if (route != null && route.fromCache)
                              const Text(
                                'Offline: showing your saved route and map',
                                style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      if (km == null && _locationNote != null)
                        TextButton(
                          onPressed: () async {
                            await Geolocator.openLocationSettings();
                            _startLocation();
                          },
                          child: const Text('Settings'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _openDirections,
                      icon: const Icon(Icons.directions),
                      label: const Text('Get directions'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDistance(double meters) =>
    meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';

String _formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

class _ResortPin extends StatelessWidget {
  const _ResortPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary]),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x550F766E), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.beach_access_rounded, color: Colors.white, size: 20),
        ),
        CustomPaint(size: const Size(12, 8), painter: _PinTail()),
      ],
    );
  }
}

class _PinTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.info.withValues(alpha: 0.22),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.info,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.primary : Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: const Color(0x330F172A),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: onTap == null ? AppColors.muted : (active ? Colors.white : AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}
