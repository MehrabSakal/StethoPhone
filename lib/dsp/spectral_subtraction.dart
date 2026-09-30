import 'dart:math' as math;

/// PASS 3: Smooth Natural Airflow Noise Floor Management.
class SpectralSubtraction {
  static List<double> reduceStationaryNoise(List<double> input, int sampleRate) {
    if (input.isEmpty) return [];

    final int n = input.length;
    final List<double> output = List.filled(n, 0.0);

    // 1. Track moving RMS envelope (~60 ms window)
    final double alpha = math.exp(-1.0 / (0.06 * sampleRate));
    final List<double> rms = List.filled(n, 0.0);
    double currentRms = 0.0;
    double minRms = double.infinity;

    final int warmup = math.min(n, (0.2 * sampleRate).round());
    for (int i = 0; i < n; i++) {
      final double sq = input[i] * input[i];
      currentRms = alpha * currentRms + (1.0 - alpha) * sq;
      final double r = math.sqrt(currentRms);
      rms[i] = r;
      if (i > warmup && r < minRms && r > 1e-6) {
        minRms = r;
      }
    }

    final double noiseFloor = (minRms < double.infinity && minRms > 0) ? minRms * 1.8 : 0.004;
    const double gateFloorGain = 0.30; // Gentle -10.5 dB reduction during silent pauses

    double currentGate = 1.0;
    final double gateAlpha = math.exp(-1.0 / (0.04 * sampleRate));

    for (int i = 0; i < n; i++) {
      final double r = rms[i];
      final double targetGain = (r < noiseFloor) ? gateFloorGain : 1.0;

      currentGate = gateAlpha * currentGate + (1.0 - gateAlpha) * targetGain;
      output[i] = input[i] * currentGate;
    }

    return output;
  }
}
