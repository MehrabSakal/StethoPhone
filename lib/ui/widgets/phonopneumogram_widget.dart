import 'package:flutter/material.dart';
import '../../dsp/ppg_analyzer.dart';

/// Interactive Phonopneumogram (Acoustic Respiratory PPG) widget.
class PhonopneumogramWidget extends StatelessWidget {
  final PpgAnalysisResult ppgResult;
  final double durationSec;

  const PhonopneumogramWidget({
    super.key,
    required this.ppgResult,
    required this.durationSec,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (ppgResult.envelope.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Extracting acoustic respiratory envelope (PPG)…'),
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
          // Header with detected respiratory rate
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.air_rounded, color: Color(0xFF00897B), size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Phonopneumogram (Acoustic PPG)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 12, color: Color(0xFF00695C)),
                    const SizedBox(width: 4),
                    Text(
                      '${ppgResult.estimatedBpm} Breaths/min',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00695C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Smoothed acoustic respiratory volume envelope with detected inhalation & exhalation peaks.',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          // PPG Wave Canvas
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _PpgWaveformPainter(
                envelope: ppgResult.envelope,
                peakIndices: ppgResult.breathPeakIndices,
                waveColor: const Color(0xFF00897B),
                fillColor: const Color(0xFF80CBC4).withOpacity(0.25),
                peakColor: const Color(0xFFE53935),
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),

          // Time scale
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0.0s', style: TextStyle(fontSize: 10, color: Colors.grey)),
              Text(
                '${ppgResult.breathPeakIndices.length} breath phases detected',
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              Text('${durationSec.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PpgWaveformPainter extends CustomPainter {
  final List<double> envelope;
  final List<int> peakIndices;
  final Color waveColor;
  final Color fillColor;
  final Color peakColor;

  _PpgWaveformPainter({
    required this.envelope,
    required this.peakIndices,
    required this.waveColor,
    required this.fillColor,
    required this.peakColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (envelope.isEmpty) return;

    final double dx = size.width / (envelope.length - 1);
    final Path wavePath = Path();
    final Path fillPath = Path();

    wavePath.moveTo(0, size.height - (envelope[0] * (size.height - 12)));
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height - (envelope[0] * (size.height - 12)));

    for (int i = 1; i < envelope.length; i++) {
      final double x = i * dx;
      final double y = size.height - (envelope[i] * (size.height - 12));
      wavePath.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Fill under curve
    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;
    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = waveColor;
    canvas.drawPath(wavePath, strokePaint);

    // Draw peak markers (Inspiratory / Expiratory points)
    final Paint peakPaint = Paint()..color = peakColor;
    for (int idx in peakIndices) {
      if (idx < envelope.length) {
        final double px = idx * dx;
        final double py = size.height - (envelope[idx] * (size.height - 12));

        canvas.drawCircle(Offset(px, py), 4.5, peakPaint);
        canvas.drawCircle(Offset(px, py), 2.0, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PpgWaveformPainter oldDelegate) =>
      oldDelegate.envelope != envelope || oldDelegate.peakIndices != peakIndices;
}
