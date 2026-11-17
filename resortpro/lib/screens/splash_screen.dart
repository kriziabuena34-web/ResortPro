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
          precacheImage(const AssetImage('assets/images/aryana_logo.png'), context),
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
      backgroundColor: AppColors.ink,
      body: Container(
        // Kapareho ng kulay ng board (ink/navy) sa Home at Account.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.ink, Color(0xFF102739), Color(0xFF1E3A55)],
          ),
        ),
        child: Stack(
          children: [
            // Malambot na liwanag sa likod ng logo
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.38),
                    radius: 0.75,
                    colors: [Color(0x332DD4BF), Color(0x00102739)],
                  ),
                ),
              ),
            ),

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

                  // Logo na palutang-lutang, may umiikot na singsing
                  AnimatedBuilder(
                    animation: _wave,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, math.sin(_wave.value * 2 * math.pi) * 6),
                      child: SizedBox(
                        width: 184,
                        height: 184,
                        child: CustomPaint(
                          painter: _OrbitPainter(_wave.value),
                          child: Center(child: child),
                        ),
                      ),
                    ),
                    child: Container(
                      width: 148,
                      height: 148,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x802DD4BF), blurRadius: 34, spreadRadius: -6),
                          BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 14)),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/aryana_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) =>
                            const Icon(Icons.hotel, color: Colors.white, size: 64),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'ResortPro',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Naka-highlight na pangalan ng resort
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 7, 16, 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.26),
                          AppColors.accent.withValues(alpha: 0.10),
                        ],
                      ),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(color: AppColors.accent.withValues(alpha: 0.18), blurRadius: 18),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.house_rounded, size: 16, color: Color(0xFFF3D08A)),
                        SizedBox(width: 8),
                        Text(
                          "Aryana's Guests House",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFFF8E3B5),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Loading: alon na linya + life ring na may porsyento
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: SizedBox(
                      height: 96,
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
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(_error ?? _status),
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _error == null
                              ? Colors.white.withValues(alpha: 0.10)
                              : const Color(0x66F87171),
                        ),
                      ),
                      child: Text(
                        _error ?? _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _error == null ? AppColors.inkText : const Color(0xFFFECACA),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
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

/// Manipis na singsing na umiikot sa paligid ng logo.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.phase);
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 3;

    // Mahinang buong bilog
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Umiikot na arko na may kumikinang na dulo
    final angle = phase * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(
      rect,
      angle,
      math.pi * 0.9,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 0.9,
          colors: const [Color(0x002DD4BF), Color(0xFF5EEAD4)],
          transform: GradientRotation(angle),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    final tip = center + Offset(math.cos(angle + math.pi * 0.9), math.sin(angle + math.pi * 0.9)) * r;
    canvas.drawCircle(
      tip,
      6,
      Paint()
        ..color = const Color(0x665EEAD4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(tip, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.phase != phase;
}

/// Ang loading line (alon) at ang life ring sa dulo nito.
class _WaveProgress extends StatelessWidget {
  const _WaveProgress({required this.progress, required this.phase, required this.percent});

  final double progress; // 0..1
  final double phase; // 0..1, galaw ng alon
  final int percent;

  static const ringSize = 60.0;

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
              top: waveY - ringSize / 2 - 12 + bob,
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

    // Track (hindi pa napupuno): madilim na channel na may manipis na gilid
    final track = _path(start, end, width);
    canvas.drawPath(
      track,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      track,
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    if (filledTo <= start + 1) return;
    final filled = _path(start, filledTo, width);
    final shaderRect = Rect.fromLTWH(start, 0, math.max(1, filledTo - start), size.height);

    // Liwanag sa likod ng napunong bahagi
    canvas.drawPath(
      filled,
      Paint()
        ..color = const Color(0xFF2DD4BF).withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Napunong bahagi ng loading
    canvas.drawPath(
      filled,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF2DD4BF), Color(0xFF99F6E4)],
        ).createShader(shaderRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    // Manipis na kinang sa ibabaw (parang tubig)
    canvas.drawPath(
      filled.shift(const Offset(0, -1.6)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    // Maliliit na bula na lumulutang sa napunong bahagi
    final bubble = Paint();
    for (var i = 0; i < 6; i++) {
      final t = (phase + i / 6) % 1.0;
      final bx = start + (filledTo - start) * ((i * 0.37 + 0.11) % 1.0);
      final by = lineY + waveOffset(bx, width, phase) - 6 - t * 18;
      bubble.color = Colors.white.withValues(alpha: 0.5 * (1 - t));
      canvas.drawCircle(Offset(bx, by), 1.6 * (1 - t) + 0.4, bubble);
    }
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
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
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
    final outer = size.width / 2 - 1;
    final thickness = outer * 0.40;
    final inner = outer - thickness;
    final mid = outer - thickness / 2;
    final rect = Rect.fromCircle(center: center, radius: mid);

    // Anino sa tubig
    canvas.drawCircle(
      center.translate(0, 4),
      outer,
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Pula at puting bahagi (8 segment), may 3D na lilim
    const segments = 8;
    const sweep = 2 * math.pi / segments;
    for (var i = 0; i < segments; i++) {
      final red = i.isEven;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep,
        sweep,
        false,
        Paint()
          ..shader = RadialGradient(
            colors: red
                ? const [Color(0xFFB91C1C), Color(0xFFEF4444), Color(0xFFB91C1C)]
                : const [Color(0xFFCBD5E1), Colors.white, Color(0xFFCBD5E1)],
            stops: [inner / outer, mid / outer, 1],
          ).createShader(Rect.fromCircle(center: center, radius: outer))
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
    }

    // Lubid sa paligid (may tali sa bawat puting bahagi)
    final rope = Paint()
      ..color = const Color(0xFFF5E6C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, mid, rope);
    for (var i = 0; i < segments; i++) {
      if (i.isEven) continue;
      final a = -math.pi / 2 + (i + 0.5) * sweep;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (inner + 1), center + dir * (outer - 1), rope..strokeWidth = 2.2);
    }

    // Kinang sa itaas-kaliwa
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outer - 3),
      math.pi * 1.05,
      math.pi * 0.45,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Mga gilid
    final edge = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, outer, edge);
    canvas.drawCircle(center, inner, edge);

    // Butas sa gitna (navy) para mabasa ang porsyento
    canvas.drawCircle(center, inner - 0.5, Paint()..color = AppColors.ink);
    canvas.drawCircle(
      center,
      inner - 0.5,
      Paint()
        ..color = const Color(0xFF2DD4BF).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
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
    _wave(canvas, size, h * 0.80, 10, 1.4, 1, const Color(0xFF2DD4BF).withValues(alpha: 0.07));
    _wave(canvas, size, h * 0.85, 12, 1.1, -1, const Color(0xFF38BDF8).withValues(alpha: 0.07));
    _wave(canvas, size, h * 0.91, 8, 1.8, 2, AppColors.ink.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant _SeaPainter old) => old.phase != phase;
}
