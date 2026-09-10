import 'dart:math' as math;
import 'package:flutter/material.dart';

class SupercarGauge extends StatefulWidget {
  final String label;
  final String unit;
  final double value;
  final double maxValue;
  final int divisions;
  final Color color;

  const SupercarGauge({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.maxValue,
    this.divisions = 10,
    this.color = const Color(0xFFFF3B30),
  });

  @override
  State<SupercarGauge> createState() => _SupercarGaugeState();
}

class _SupercarGaugeState extends State<SupercarGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(SupercarGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
      _animation = Tween<double>(begin: _previousValue, end: widget.value).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      );
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(200, 200),
          painter: _GaugePainter(
            value: _animation.value,
            maxValue: widget.maxValue,
            divisions: widget.divisions,
            label: widget.label,
            unit: widget.unit,
            color: widget.color,
          ),
        );
      },
    );
  }
}


class _GaugePainter extends CustomPainter {
  final double value;
  final double maxValue;
  final int divisions;
  final String label;
  final String unit;
  final Color color;

  _GaugePainter({
    required this.value,
    required this.maxValue,
    required this.divisions,
    required this.label,
    required this.unit,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..shader = SweepGradient(
        startAngle: math.pi * 0.75,
        endAngle: math.pi * 2.25,
        colors: [color.withOpacity(0.3), color, color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (value / maxValue) * math.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      sweepAngle,
      false,
      valuePaint,
    );

    // Tick marks
    for (int i = 0; i <= divisions; i++) {
      final angle = math.pi * 0.75 + (i / divisions) * math.pi * 1.5;
      final isMain = i % 2 == 0;
      final innerRadius = radius - (isMain ? 25 : 18);
      final outerRadius = radius - 8;

      final tickPaint = Paint()
        ..color = isMain ? Colors.white : Colors.grey.shade600
        ..strokeWidth = isMain ? 2 : 1;

      canvas.drawLine(
        Offset(center.dx + innerRadius * math.cos(angle), center.dy + innerRadius * math.sin(angle)),
        Offset(center.dx + outerRadius * math.cos(angle), center.dy + outerRadius * math.sin(angle)),
        tickPaint,
      );
    }

    // Needle
    final needleAngle = math.pi * 0.75 + sweepAngle;
    final needlePaint = Paint()
      ..color = const Color(0xFFFF3B30)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(center.dx + (radius - 35) * math.cos(needleAngle), center.dy + (radius - 35) * math.sin(needleAngle)),
      needlePaint,
    );

    // Center dot
    canvas.drawCircle(center, 8, Paint()..color = const Color(0xFFFF3B30));
    canvas.drawCircle(center, 4, Paint()..color = Colors.black);

    // Value text
    final valueSpan = TextSpan(
      text: value.toStringAsFixed(0),
      style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
    );
    final valuePainter = TextPainter(text: valueSpan, textDirection: TextDirection.ltr);
    valuePainter.layout();
    valuePainter.paint(canvas, Offset(center.dx - valuePainter.width / 2, center.dy + 20));

    // Unit text
    final unitSpan = TextSpan(
      text: unit,
      style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500),
    );
    final unitPainter = TextPainter(text: unitSpan, textDirection: TextDirection.ltr);
    unitPainter.layout();
    unitPainter.paint(canvas, Offset(center.dx - unitPainter.width / 2, center.dy + 55));

    // Label text
    final labelSpan = TextSpan(
      text: label,
      style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 2),
    );
    final labelPainter = TextPainter(text: labelSpan, textDirection: TextDirection.ltr);
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(center.dx - labelPainter.width / 2, center.dy - 50));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.value != value;
}