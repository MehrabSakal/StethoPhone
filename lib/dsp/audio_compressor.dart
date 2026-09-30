import 'dart:math' as math;

/// Smooth, non-distorting dynamics and acoustic gain stage for respiratory auscultation.
class AudioCompressor {
  static const double peakHeadroomTarget = 0.85; // -1.4 dBFS safe digital ceiling
  static const double softKneeStart = 0.70;      // Soft saturation onset

  static List<double> processDynamicsAndGain(List<double> input, int sampleRate, double requestedGain) {
    if (input.isEmpty) return [];

    final int n = input.length;
    final List<double> output = List.filled(n, 0.0);

    // 1. Find true maximum peak
    double maxPeak = 0.0001;
    for (final s in input) {
      final double abs = s.abs();
      if (abs > maxPeak) {
        maxPeak = abs;
      }
    }

    // 2. Compute Clean Linear Gain Factor
    final double maxCleanGain = peakHeadroomTarget / maxPeak;
    final double effectiveGain = (requestedGain <= 0)
        ? maxCleanGain
        : math.min(requestedGain, maxCleanGain * 1.05);

    // 3. Smooth Hyperbolic Tangent Soft Limiter (Zero Digital Hard-Clipping)
    for (int i = 0; i < n; i++) {
      final double sample = input[i] * effectiveGain;
      final double abs = sample.abs();
      double smoothSample;

      if (abs > softKneeStart) {
        final double delta = abs - softKneeStart;
        final double kneeRange = 1.0 - softKneeStart;
        // Hyperbolic tangent soft saturation
        final double tanhVal = (math.exp(2 * (delta / (kneeRange * 0.5))) - 1) /
                               (math.exp(2 * (delta / (kneeRange * 0.5))) + 1);
        final double saturated = softKneeStart + (kneeRange * 0.5) * tanhVal;
        smoothSample = sample.sign * math.min(peakHeadroomTarget, saturated);
      } else {
        smoothSample = sample;
      }

      output[i] = smoothSample;
    }

    return output;
  }
}
