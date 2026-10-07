import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScanShutterButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool busy;

  const ScanShutterButton({super.key, this.onTap, this.busy = false});

  @override
  State<ScanShutterButton> createState() => _ScanShutterButtonState();
}

class _ScanShutterButtonState extends State<ScanShutterButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _press.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onTap != null && !widget.busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: _enabled ? (_) => _press.forward() : null,
          onTapCancel: () => _press.reverse(),
          onTapUp: _enabled
              ? (_) {
                  _press.reverse();
                  widget.onTap!();
                }
              : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _press]),
            builder: (context, _) {
              final pulse = _pulse.value;
              final scale = 1.0 - (_press.value * 0.12);
              return Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing glow ring
                      Container(
                        width: 84 + (pulse * 12),
                        height: 84 + (pulse * 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary
                                .withOpacity(0.55 - (pulse * 0.4)),
                            width: 2,
                          ),
                        ),
                      ),
                      // Outer white ring
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black38,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.45),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      // Inner gradient circle
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white,
                              AppColors.primary.withOpacity(0.85),
                            ],
                          ),
                        ),
                        child: widget.busy
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.document_scanner_rounded,
                                color: Colors.black87,
                                size: 28,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.busy ? 'Capturing…' : 'Tap to scan',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}