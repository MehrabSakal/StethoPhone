import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A stacked comparative waveform visualizer showing Raw vs Amplified acoustic waveforms.
class ComparisonWaveformWidget extends StatelessWidget {
  final List<double> rawSamples;
  final List<double> cleanedSamples;
  final double durationSec;

  const ComparisonWaveformWidget({
    super.key,
    required this.rawSamples,
    required this.cleanedSamples,
    required this.durationSec,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.compare_arrows_rounded, color: Color(0xFF00897B), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Acoustic Waveform Comparison',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${durationSec.toStringAsFixed(1)}s Span',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Raw Waveform Section
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF78909C), // Slate grey
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '1. Actual Sound (Raw PCM)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF78909C)),
              ),
              const Spacer(),
              const Text('1.0x Base • Low Signal-to-Noise', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 75,
              color: colorScheme.surfaceVariant.withOpacity(0.35),
              child: CustomPaint(
                painter: _SingleWavePainter(
                  samples: rawSamples,
                  waveColor: const Color(0xFF78909C),
                  normalizeToMax: false,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Amplified & Cleaned Waveform Section
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00897B), // Teal
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '2. Cleaned & 10x Amplified Sound',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00897B)),
              ),
              const Spacer(),
              const Text('10x Boost • 5-Pass DSP Applied', style: TextStyle(fontSize: 10, color: Color(0xFF00897B))),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 75,
              color: const Color(0xFF00897B).withOpacity(0.08),
              child: CustomPaint(
                painter: _SingleWavePainter(
                  samples: cleanedSamples.isNotEmpty ? cleanedSamples : rawSamples,
                  waveColor: const Color(0xFF00897B),
                  normalizeToMax: true,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'Notice the suppression of low-frequency heart beat bursts and elevation of high-frequency vesicular murmur acoustics in the amplified stream.',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

class _SingleWavePainter extends CustomPainter {
  final List<double> samples;
  final Color waveColor;
  final bool normalizeToMax;

  _SingleWavePainter({
    required this.samples,
    required this.waveColor,
    required this.normalizeToMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final centerLinePaint = Paint()
      ..color = waveColor.withOpacity(0.2)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final double midY = size.height / 2.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), centerLinePaint);

    final path = Path();
    final int points = size.width.toInt().clamp(50, 600);
    final int step = math.max(1, samples.length ~/ points);

    double maxVal = 0.001;
    if (normalizeToMax) {
      for (int i = 0; i < samples.length; i += step) {
        final abs = samples[i].abs();
        if (abs > maxVal) maxVal = abs;
      }
    } else {
      maxVal = 1.0; // absolute raw scaling
    }

    bool started = false;
    for (int x = 0; x < points; x++) {
      final int idx = x * step;
      if (idx >= samples.length) break;

      final double sample = samples[idx];
      final double normalized = (sample / maxVal).clamp(-1.0, 1.0);
      final double y = midY - (normalized * (size.height / 2.2));
      final double px = (x / points) * size.width;

      if (!started) {
        path.moveTo(px, y);
        started = true;
      } else {
        path.lineTo(px, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SingleWavePainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.waveColor != waveColor;
  }
}
