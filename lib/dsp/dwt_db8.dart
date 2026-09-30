import 'dart:math' as math;

/// PASS 2: Smooth Acoustic Artifact and Transient Attenuation.
class DwtDb8 {
  static List<double> separateHeartAndArtifacts(List<double> input, int sampleRate) {
    if (input.isEmpty) return [];

    final int n = input.length;
    final List<double> output = List.filled(n, 0.0);

    // Smooth transient limiter:
    // Detects isolated sharp impulse clicks (friction on mic housing) without modifying
    // the continuous, soft, stochastic wave shapes of inhalation and exhalation.
    double meanEnergy = 0.0;
    for (final s in input) {
      meanEnergy += s * s;
    }
    meanEnergy /= n;
    final double rms = math.sqrt(meanEnergy);
    final double transientCeiling = math.max(0.40, rms * 4.5);

    for (int i = 0; i < n; i++) {
      final double s = input[i];
      final double abs = s.abs();

      if (abs > transientCeiling) {
        final double excess = abs - transientCeiling;
        // tanh approximation
        final double tanhVal = (math.exp(2 * (excess / 0.10)) - 1) / (math.exp(2 * (excess / 0.10)) + 1);
        final double compressed = transientCeiling + 0.10 * tanhVal;
        output[i] = s.sign * compressed;
      } else {
        output[i] = s;
      }
    }

    return output;
  }
}
