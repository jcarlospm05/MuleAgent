import 'dart:math';
import 'package:flutter/material.dart';

/// One orbit, with no delay in capture and no animation when Android requests it.
class MeterBorder extends StatefulWidget {
  const MeterBorder({super.key, required this.child});
  final Widget child;
  @override
  State<MeterBorder> createState() => _MeterBorderState();
}

class _MeterBorderState extends State<MeterBorder>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      if (!MediaQuery.disableAnimationsOf(context)) controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) =>
        CustomPaint(foregroundPainter: _Orbit(controller.value), child: child),
    child: widget.child,
  );
}

class _Orbit extends CustomPainter {
  _Orbit(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      );
    final metric = path.computeMetrics().first;
    final start = progress * metric.length;
    final end = start + metric.length * .16;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFFC45B);
    canvas.drawPath(metric.extractPath(start, min(end, metric.length)), paint);
    if (end > metric.length) {
      canvas.drawPath(metric.extractPath(0, end - metric.length), paint);
    }
  }

  @override
  bool shouldRepaint(_Orbit oldDelegate) => oldDelegate.progress != progress;
}
