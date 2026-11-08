import 'package:flutter/material.dart';

/// Same mark as the Android launcher resource, drawn at any display density.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Logo de MuleAgent',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(size: Size.square(size), painter: _LogoPainter()),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 48, 48),
      Paint()..color = const Color(0xFF21355E),
    );
    final mark = Path()
      ..moveTo(9, 34)
      ..lineTo(9, 14)
      ..lineTo(15, 14)
      ..lineTo(24, 25)
      ..lineTo(33, 14)
      ..lineTo(39, 14)
      ..lineTo(39, 34)
      ..lineTo(33, 34)
      ..lineTo(33, 23)
      ..lineTo(24, 34)
      ..lineTo(15, 23)
      ..lineTo(15, 34)
      ..close();
    canvas.drawPath(mark, Paint()..color = const Color(0xFFFFC45B));
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
