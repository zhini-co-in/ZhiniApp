import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ZhiniThinkingView extends StatefulWidget {
  const ZhiniThinkingView({super.key});

  @override
  State<ZhiniThinkingView> createState() => _ZhiniThinkingViewState();
}

class _ZhiniThinkingViewState extends State<ZhiniThinkingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _textTimer;
  int _msgIndex = 0;

  static const _messages = [
    'Looking at your appliance…',
    'Reading the brand…',
    'Checking warranty details…',
    'Finding service centers near you…',
    'Almost there…',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    _textTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/zhini_genie.png'), context);
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF050E1F),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          final wave = (math.sin(t * 2 * math.pi) + 1) / 2; // 0..1

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Deep magical background glow
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.9 + 0.1 * wave,
                    colors: const [Color(0xFF16406B), Color(0xFF050E1F)],
                  ),
                ),
              ),

              // 2. Full-screen ZHINI (breathing zoom + float)
              Transform.translate(
                offset: Offset(0, -10 * wave),
                child: Transform.scale(
                  scale: 1.0 + 0.04 * wave,
                  child: Image.asset(
                    'assets/zhini_genie.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),

              // 3. Rising sparkles
              CustomPaint(painter: _SparklePainter(t)),

              // 4. Bottom fade so text is readable
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.of(context).size.height * 0.4,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xEE050E1F)],
                    ),
                  ),
                ),
              ),

              // 5. Text + dots
              Positioned(
                left: 24,
                right: 24,
                bottom: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (rect) => LinearGradient(
                        begin: Alignment(-1.5 + 3 * t, 0),
                        end: Alignment(-0.5 + 3 * t, 0),
                        colors: const [
                          Color(0xFF81D4FA),
                          Colors.white,
                          Color(0xFF81D4FA),
                        ],
                      ).createShader(rect),
                      child: const Text(
                        'ZHINI is thinking',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final p = (t * 3 - i * 0.25) % 1.0;
                        final s = 0.6 + 0.6 * math.sin(p * math.pi).abs();
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 9 * s,
                          height: 9 * s,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _messages[_msgIndex],
                        key: ValueKey(_msgIndex),
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Spark {
  final double x, size, phase;
  final int speed;
  const _Spark(this.x, this.size, this.phase, this.speed);
}

class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter(this.t);

  static final List<_Spark> _sparks = () {
    final r = math.Random(7);
    return List.generate(
      34,
      (_) => _Spark(r.nextDouble(), 1.5 + r.nextDouble() * 3.5, r.nextDouble(), 1 + r.nextInt(3)),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _sparks) {
      final p = (t * s.speed + s.phase) % 1.0; // 0 bottom -> 1 top
      final y = size.height * (1 - p);
      final x = size.width * s.x + math.sin((p + s.phase) * 2 * math.pi) * 14;
      final alpha = math.sin(p * math.pi); // fade in & out
      final paint = Paint()
        ..color = const Color(0xFFB3E5FC).withValues(alpha: alpha * 0.9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.size);
      canvas.drawCircle(Offset(x, y), s.size, paint);
      if (s.size > 3.2) {
        final star = Paint()..color = Colors.white.withValues(alpha: alpha);
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: s.size * 3, height: 1.2), star);
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 1.2, height: s.size * 3), star);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.t != t;
}