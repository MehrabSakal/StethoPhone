import 'dart:math' as math;

/// PASS 4: Dynamics & Amplification in Dart (Compressor 4:1 + Makeup Gain + Limiter -0.5 dBFS).
class AudioCompressor {
  static const double hardLimiterCeiling = 0.944; // -0.5 dBFS
  static const double defaultThresholdDb = -22.0;
  static const double compressionRatio = 4.0; // 4:1 ratio
  static const double attackTimeSec = 0.005; // 5ms
  static const double releaseTimeSec = 0.070; // 70ms

  static List<double> processDynamicsAndGain(List<double> input, int sampleRate, double requestedMakeupGain) {
    if (input.isEmpty) return [];

    final int n = input.length;
    final List<double> compressed = List.filled(n, 0.0);

    final double alphaAtt = math.exp(-1.0 / (attackTimeSec * sampleRate));
    final double alphaRel = math.exp(-1.0 / (releaseTimeSec * sampleRate));
    double env = 0.0;

    for (int i = 0; i < n; i++) {
      final double absX = input[i].abs();

      if (absX > env) {
        env = alphaAtt * env + (1.0 - alphaAtt) * absX;
      } else {
        env = alphaRel * env + (1.0 - alphaRel) * absX;
      }

      final double envDb = (env > 1e-6) ? 20.0 * math.log(env) / math.ln10 : -120.0;

      double gainDb = 0.0;
      if (envDb > defaultThresholdDb) {
        gainDb = (defaultThresholdDb + (envDb - defaultThresholdDb) / compressionRatio) - envDb;
      }

      final double compGain = math.pow(10.0, gainDb / 20.0).toDouble();
      compressed[i] = input[i] * compGain;
    }

    // Makeup Gain
    double maxCompPeak = 0.0;
    for (final v in compressed) {
      final double abs = v.abs();
      if (abs > maxCompPeak) {
        maxCompPeak = abs;
      }
    }

    final double maxSafeGain = (maxCompPeak > 0.0001) ? (hardLimiterCeiling / maxCompPeak) : 1.0;
    final double appliedMakeupGain = (requestedMakeupGain <= 0)
        ? maxSafeGain
        : math.min(requestedMakeupGain, maxSafeGain * 1.25);

    // Limiter at -0.5 dBFS
    final List<double> output = List.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      final double amplified = compressed[i] * appliedMakeupGain;
      output[i] = amplified.clamp(-hardLimiterCeiling, hardLimiterCeiling);
    }

    return output;
  }
}
