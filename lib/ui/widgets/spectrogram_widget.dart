import 'package:flutter/material.dart';

/// Interactive Spectrogram (STFT) visualization widget.
class SpectrogramWidget extends StatelessWidget {
  final List<List<double>> spectrogram;
  final double durationSec;
  final double maxFreqHz;

  const SpectrogramWidget({
    super.key,
    required this.spectrogram,
    required this.durationSec,
    this.maxFreqHz = 2500.0,
  });

  @override
  Widget build(BuildContext context) {
    if (spectrogram.isEmpty) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Computing STFT Spectrogram…',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }

    return Container(
      height: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Spectrogram Heatmap (STFT 0 – 2.5 kHz)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  const Text('Low', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  const SizedBox(width: 4),
                  Container(
                    width: 60,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0B1120),
                          Color(0xFF00897B),
                          Color(0xFFFFB300),
                          Color(0xFFE53935),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('High', style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Spectrogram canvas with frequency Y-axis
          Expanded(
            child: Row(
              children: [
                // Y-Axis labels (Frequency)
                SizedBox(
                  width: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${(maxFreqHz / 1000).toStringAsFixed(1)}k', style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                      const Text('1.5k', style: TextStyle(color: Colors.white54, fontSize: 9.5)),
                      const Text('800', style: TextStyle(color: Colors.white54, fontSize: 9.5)),
                      const Text('200', style: TextStyle(color: Colors.white54, fontSize: 9.5)),
                      const Text('0 Hz', style: TextStyle(color: Colors.white54, fontSize: 9.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // Heatmap Canvas
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _SpectrogramPainter(spectrogram),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // X-Axis labels (Time)
          Padding(
            padding: const EdgeInsets.only(left: 54.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0.0s', style: TextStyle(color: Colors.white54, fontSize: 9.5)),
                Text('${(durationSec * 0.5).toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                Text('${durationSec.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpectrogramPainter extends CustomPainter {
  final List<List<double>> spectrogram;

  _SpectrogramPainter(this.spectrogram);

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrogram.isEmpty) return;

    final int numFrames = spectrogram.length;
    final int numBins = spectrogram[0].length;
    final double colWidth = size.width / numFrames;
    final double rowHeight = size.height / numBins;

    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int t = 0; t < numFrames; t++) {
      final double x = t * colWidth;
      final List<double> spectrum = spectrogram[t];

      for (int f = 0; f < numBins; f++) {
        // High frequencies at top (y=0), low frequencies at bottom (y=size.height)
        final double y = size.height - ((f + 1) * rowHeight);
        final double intensity = spectrum[f];

        paint.color = _getHeatmapColor(intensity);
        canvas.drawRect(
          Rect.fromLTWH(x, y, colWidth + 0.5, rowHeight + 0.5),
          paint,
        );
      }
    }
  }

  Color _getHeatmapColor(double value) {
    final double v = value.clamp(0.0, 1.0);
    if (v < 0.25) {
      final double t = v / 0.25;
      return Color.lerp(const Color(0xFF0B1120), const Color(0xFF004D40), t)!;
    } else if (v < 0.55) {
      final double t = (v - 0.25) / 0.30;
      return Color.lerp(const Color(0xFF004D40), const Color(0xFF00897B), t)!;
    } else if (v < 0.80) {
      final double t = (v - 0.55) / 0.25;
      return Color.lerp(const Color(0xFF00897B), const Color(0xFFFFB300), t)!;
    } else {
      final double t = (v - 0.80) / 0.20;
      return Color.lerp(const Color(0xFFFFB300), const Color(0xFFE53935), t)!;
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter oldDelegate) =>
      oldDelegate.spectrogram != spectrogram;
}
