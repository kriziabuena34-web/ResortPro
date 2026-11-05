import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/notifications.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';
import 'sign_in_page.dart';

/// Isang beses lang dapat i-initialize ang Supabase sa bawat pagbukas ng app.
bool _supabaseReady = false;

/// Loading screen ng ResortPro.
/// Habang naglo-load ang app (Supabase, notifications, litrato), may loading
/// line na alon, at sa dulo nito ay may life ring (salbabida) na may porsyento.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Gumagalaw na alon (tuloy-tuloy)
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  // Ang ipinapakitang porsyento ay dahan-dahang humahabol sa totoong progress.
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(days: 1),
  )..addListener(_tick);

  double _target = 0.05; // totoong progress ng loading
  double _shown = 0; // ipinapakita sa screen
  String _status = 'Starting up…';
  String? _error;
  Widget? _next;

  /// Pinakamaikling tagal ng loading screen (para makita ang animation).
  static const _minDuration = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    _ticker.forward();
    _load();
  }

  @override
  void dispose() {
    _wave.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _tick() {
    // Humahabol nang malambot; hindi lalampas sa target.
    final next = _shown + (_target - _shown) * 0.06 + 0.0015;
    final value = math.min(next, _target);
    if ((value - _shown).abs() < 0.0001) return;
    setState(() => _shown = value);

    if (_shown >= 0.999 && _next != null) {
      final page = _next!;
      _next = null;
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (context, animation, secondaryAnimation) => page,
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      });
    }
  }

  void _step(double progress, String status) {
    if (!mounted) return;
    setState(() {
      _target = math.max(_target, progress);
      _status = status;
    });
  }

  Future<void> _load() async {
    final started = DateTime.now();
    setState(() {
      _error = null;
      _target = math.max(_target, 0.12);
    });

    // 1) Database at login
    _step(0.15, 'Connecting to Aryana\'s Guests House…');
    try {
      if (!_supabaseReady) {
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
        _supabaseReady = true;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not connect. Please check your internet and try again.');
      return;
    }
    _step(0.5, 'Getting things ready…');

    // 2) Phone notifications at background check
    try {
      await LocalNotifier.init();
      await BackgroundCheck.initialize();
    } catch (_) {
      // Hindi dapat pigilan ng notifications ang pagbukas ng app.
    }
    _step(0.72, 'Preparing your stay…');

    // 3) Litrato para mabilis lumabas ang unang screen
    if (mounted) {
      try {
        await Future.wait([
          precacheImage(const AssetImage('assets/images/backless.png'), context),
          precacheImage(const AssetImage('assets/images/pic1.jpg'), context),
        ]);
      } catch (_) {}
    }
    _step(0.9, 'Almost there…');

    // 4) Saan pupunta: Home kung naka-login, Sign in kung hindi pa
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    final page = signedIn ? const HomePage() : const SignInPage();

    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minDuration) await Future.delayed(_minDuration - elapsed);
    if (!mounted) return;
    setState(() {
      _next = page;
      _target = 1.0;
      _status = 'Welcome!';
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_shown * 100).clamp(0, 100).round();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.ink, Color(0xFF0E4D5A), AppColors.primary],
          ),
        ),
        child: Stack(
          children: [
            // Alon ng tubig sa ibaba
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) => CustomPaint(painter: _SeaPainter(_wave.value)),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Logo na palutang-lutang
                  AnimatedBuilder(
                    animation: _wave,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, math.sin(_wave.value * 2 * math.pi) * 6),
                      child: child,
                    ),
                    child: Container(
                      width: 150,
                      height: 150,
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14)),
                        ],
                      ),
                      child: Image.asset('assets/images/backless.png', fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'ResortPro',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Aryana's Guests House",
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Loading: alon na linya + life ring na may porsyento
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: SizedBox(
                      height: 92,
                      child: AnimatedBuilder(
                        animation: _wave,
                        builder: (context, _) => _WaveProgress(
                          progress: _shown,
                          phase: _wave.value,
                          percent: percent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _error ?? _status,
                      key: ValueKey(_error ?? _status),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error == null ? const Color(0xFFCFE3E6) : const Color(0xFFFECACA),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                      ),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ang loading line (alon) at ang life ring sa dulo nito.
class _WaveProgress extends StatelessWidget {
  const _WaveProgress({required this.progress, required this.phase, required this.percent});

  final double progress; // 0..1
  final double phase; // 0..1, galaw ng alon
  final int percent;

  static const ringSize = 56.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final lineY = c.maxHeight - 18;
        // Hindi lalampas sa gilid ang life ring.
        final x = (ringSize / 2) + (width - ringSize) * progress;
        final waveY = lineY + _WavePainter.waveOffset(x, width, phase);
        final bob = math.sin(phase * 2 * math.pi * 2) * 3;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WavePainter(progress: progress, phase: phase, lineY: lineY, ringSize: ringSize),
              ),
            ),
            Positioned(
              left: x - ringSize / 2,
              top: waveY - ringSize / 2 - 10 + bob,
              child: Transform.rotate(
                angle: math.sin(phase * 2 * math.pi) * 0.12,
                child: _LifeRing(size: ringSize, percent: percent),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.phase, required this.lineY, required this.ringSize});

  final double progress;
  final double phase;
  final double lineY;
  final double ringSize;

  /// Taas ng alon sa puntong [x] (iisang formula para sa linya at sa life ring).
  static double waveOffset(double x, double width, double phase) {
    const amplitude = 5.0;
    const waves = 3.0;
    return math.sin((x / width) * waves * 2 * math.pi - phase * 2 * math.pi) * amplitude;
  }

  Path _path(double fromX, double toX, double width) {
    final path = Path();
    for (var x = fromX; x <= toX; x += 2) {
      final y = lineY + waveOffset(x, width, phase);
      if (x == fromX) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final start = ringSize / 2;
    final end = width - ringSize / 2;
    final filledTo = start + (end - start) * progress;

    // Track (hindi pa napupuno)
    canvas.drawPath(
      _path(start, end, width),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    if (filledTo <= start + 1) return;

    // Liwanag sa likod ng napunong bahagi
    canvas.drawPath(
      _path(start, filledTo, width),
      Paint()
        ..color = const Color(0xFF5EEAD4).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Napunong bahagi ng loading
    canvas.drawPath(
      _path(start, filledTo, width),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF14B8A6), Color(0xFF5EEAD4), Colors.white])
            .createShader(Rect.fromLTWH(start, 0, math.max(1, filledTo - start), size.height))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.progress != progress || old.phase != phase;
}

/// Life ring (salbabida): puti at pula, may porsyento sa gitna.
class _LifeRing extends StatelessWidget {
  const _LifeRing({required this.size, required this.percent});
  final double size;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LifeRingPainter(),
        child: Center(
          child: Text(
            '$percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}

class _LifeRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    final thickness = outer * 0.42;
    final mid = outer - thickness / 2;
    final rect = Rect.fromCircle(center: center, radius: mid);

    // Anino
    canvas.drawCircle(
      center.translate(0, 3),
      outer,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Puti at pulang bahagi (8 segment)
    const segments = 8;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * (2 * math.pi / segments),
        2 * math.pi / segments,
        false,
        Paint()
          ..color = i.isEven ? const Color(0xFFE53935) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
    }

    // Manipis na gilid at lubid
    final edge = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, outer, edge);
    canvas.drawCircle(center, outer - thickness, edge);
    canvas.drawCircle(
      center,
      mid,
      Paint()
        ..color = const Color(0xFFF5E6C8).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Tubig sa butas para mabasa ang porsyento
    canvas.drawCircle(center, outer - thickness - 0.5, Paint()..color = AppColors.primaryDark.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mga alon ng dagat sa ibaba ng screen.
class _SeaPainter extends CustomPainter {
  _SeaPainter(this.phase);
  final double phase;

  void _wave(Canvas canvas, Size size, double baseY, double amp, double waves, double speed, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 4) {
      final y = baseY + math.sin((x / size.width) * waves * 2 * math.pi + phase * 2 * math.pi * speed) * amp;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    _wave(canvas, size, h * 0.80, 10, 1.4, 1, const Color(0xFF14B8A6).withValues(alpha: 0.16));
    _wave(canvas, size, h * 0.85, 12, 1.1, -1, const Color(0xFF5EEAD4).withValues(alpha: 0.12));
    _wave(canvas, size, h * 0.91, 8, 1.8, 2, AppColors.ink.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant _SeaPainter old) => old.phase != phase;
}
