import 'dart:math' as math;
import 'package:flutter/material.dart';

/// High-resolution Time-Expanded Waveform widget for respiratory acoustic analysis.
class TimeExpandedWaveformWidget extends StatelessWidget {
  final List<double> samples;
  final double durationSec;
  final bool isAmplified;

  const TimeExpandedWaveformWidget({
    super.key,
    required this.samples,
    required this.durationSec,
    this.isAmplified = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (samples.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Decoding high-resolution waveform…'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.timeline_rounded,
                    color: isAmplified ? colorScheme.secondary : colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAmplified ? 'Time-Expanded Waveform (10x Amplified)' : 'Time-Expanded Waveform (Raw)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isAmplified ? colorScheme.secondaryContainer : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAmplified ? 'ML READY' : 'RAW ACOUSTIC',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isAmplified ? colorScheme.onSecondaryContainer : colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'High-definition acoustic oscillogram showing breath murmurs, crackle transients, and wheeze oscillations.',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          // Waveform canvas
          SizedBox(
            height: 130,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _TimeExpandedPainter(
                  samples: samples,
                  waveColor: isAmplified ? colorScheme.secondary : colorScheme.primary,
                  gridColor: colorScheme.outlineVariant.withOpacity(0.3),
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Time scale
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0.0s', style: TextStyle(fontSize: 10, color: Colors.grey)),
              Text('${(durationSec * 0.5).toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text('${durationSec.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeExpandedPainter extends CustomPainter {
  final List<double> samples;
  final Color waveColor;
  final Color gridColor;

  _TimeExpandedPainter({
    required this.samples,
    required this.waveColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final double centerY = size.height / 2.0;

    // Draw center zero-crossing line & grid
    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), gridPaint);
    canvas.drawLine(Offset(0, centerY * 0.5), Offset(size.width, centerY * 0.5), gridPaint);
    canvas.drawLine(Offset(0, centerY * 1.5), Offset(size.width, centerY * 1.5), gridPaint);

    final Paint wavePaint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final int numPoints = math.min(samples.length, (size.width * 2).round());
    final double step = samples.length / numPoints;
    final double dx = size.width / numPoints;

    final Path path = Path();
    path.moveTo(0, centerY);

    for (int i = 0; i < numPoints; i++) {
      final int idx = (i * step).floor().clamp(0, samples.length - 1);
      final double s = samples[idx];
      final double x = i * dx;
      final double y = centerY - (s * (centerY * 0.95));
      path.lineTo(x, y);
    }

    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _TimeExpandedPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.waveColor != waveColor;
}
