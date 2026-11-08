import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/money.dart';

/// Lightweight custom line chart using native CustomPainter (zero external deps).
class SimpleLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final double height;

  const SimpleLineChart({
    super.key,
    required this.values,
    required this.labels,
    this.lineColor = const Color(0xFF00796B),
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('داده‌ای برای نمایش نمودار وجود ندارد.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _LineChartPainter(
          values: values,
          labels: labels,
          lineColor: lineColor,
          textColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final Color textColor;

  _LineChartPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPadding = 24.0;
    const topPadding = 12.0;
    const horizontalPadding = 16.0;

    final chartHeight = size.height - bottomPadding - topPadding;
    final chartWidth = size.width - (horizontalPadding * 2);

    final maxVal = values.reduce(math.max);
    final minVal = math.min(0.0, values.reduce(math.min));
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = topPadding + (chartHeight * i / 3);
      canvas.drawLine(
        Offset(horizontalPadding, y),
        Offset(size.width - horizontalPadding, y),
        gridPaint,
      );
    }

    // Calculate points
    final points = <Offset>[];
    final stepX = values.length > 1 ? chartWidth / (values.length - 1) : 0.0;

    for (var i = 0; i < values.length; i++) {
      final x = horizontalPadding + (i * stepX);
      final normalized = (values[i] - minVal) / range;
      final y = topPadding + chartHeight - (normalized * chartHeight);
      points.add(Offset(x, y));
    }

    if (points.isNotEmpty) {
      // Draw area gradient fill
      final fillPath = Path();
      fillPath.moveTo(points.first.dx, topPadding + chartHeight);
      for (final pt in points) {
        fillPath.lineTo(pt.dx, pt.dy);
      }
      fillPath.lineTo(points.last.dx, topPadding + chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.35),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight));
      canvas.drawPath(fillPath, fillPaint);

      // Draw stroke path
      final strokePath = Path();
      strokePath.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        strokePath.lineTo(points[i].dx, points[i].dy);
      }

      final linePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(strokePath, linePaint);

      // Draw point markers
      final pointPaint = Paint()..color = lineColor;
      final whitePaint = Paint()..color = Colors.white;

      for (final pt in points) {
        canvas.drawCircle(pt, 4.5, pointPaint);
        canvas.drawCircle(pt, 2.5, whitePaint);
      }
    }

    // Draw bottom labels
    final textStyle = TextStyle(fontSize: 10, color: textColor, fontFamily: 'Vazirmatn');
    for (var i = 0; i < labels.length && i < points.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: textStyle),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset(points[i].dx - (tp.width / 2), size.height - bottomPadding + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values || old.lineColor != lineColor;
}

/// Lightweight custom donut/pie chart using native CustomPainter (zero external deps).
class SimpleDonutChart extends StatelessWidget {
  final Map<String, ({int value, Color color})> segments;
  final double size;
  final double strokeWidth;

  const SimpleDonutChart({
    super.key,
    required this.segments,
    this.size = 140,
    this.strokeWidth = 22,
  });

  @override
  Widget build(BuildContext context) {
    final total = segments.values.fold<int>(0, (sum, s) => sum + s.value);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutChartPainter(
              segments: segments,
              total: total,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('مجموع', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    total > 0 ? toFaDigits('${(total / 1000000).toStringAsFixed(1)}م') : '۰',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: segments.entries.map((e) {
              final pct = total > 0 ? ((e.value.value / total) * 100).toStringAsFixed(1) : '۰';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: e.value.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${e.key} (${toFaDigits('$pct%')})',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final Map<String, ({int value, Color color})> segments;
  final int total;
  final double strokeWidth;

  _DonutChartPainter({
    required this.segments,
    required this.total,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    if (total <= 0) {
      final emptyPaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, emptyPaint);
      return;
    }

    var startAngle = -math.pi / 2;

    for (final seg in segments.values) {
      if (seg.value <= 0) continue;
      final sweepAngle = (seg.value / total) * 2 * math.pi;

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.total != total || old.segments != segments;
}
