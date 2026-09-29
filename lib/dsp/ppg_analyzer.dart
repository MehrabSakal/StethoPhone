import 'dart:math' as math;

/// Diagnostic metrics extracted from Phonopneumogram (Acoustic Respiratory PPG).
class PpgAnalysisResult {
  final List<double> envelope; // Smoothed acoustic breathing cycle envelope [0.0 - 1.0]
  final List<int> breathPeakIndices; // Detected respiratory breath peaks
  final double estimatedBpm; // Estimated Respiratory Rate (Breaths per minute)
  final double meanEnergy;
  final double peakEnergy;
  final double snrDb; // Signal to Noise Ratio in dB

  PpgAnalysisResult({
    required this.envelope,
    required this.breathPeakIndices,
    required this.estimatedBpm,
    required this.meanEnergy,
    required this.peakEnergy,
    required this.snrDb,
  });
}

/// Analyzer for Phonopneumogram (PPG) / Acoustic Respiratory Envelope.
///
/// In respiratory medicine and pulmonary diagnostics, a Phonopneumogram (PPG)
/// represents the low-frequency acoustic power envelope of the lungs over time.
/// It visualizes tidal volume airflow, inspiratory/expiratory phase dynamics,
/// and allows automated computation of the patient's respiratory rate.
class PpgAnalyzer {
  static PpgAnalysisResult analyze({
    required List<double> samples,
    required double sampleRate,
    int targetPoints = 300,
  }) {
    if (samples.isEmpty) {
      return PpgAnalysisResult(
        envelope: [],
        breathPeakIndices: [],
        estimatedBpm: 0,
        meanEnergy: 0,
        peakEnergy: 0,
        snrDb: 0,
      );
    }

    final double totalDurationSec = samples.length / sampleRate;

    // 1. Moving RMS window (~100 ms)
    final int windowSize = math.max(1, (sampleRate * 0.1).round());
    final int stepSize = math.max(1, samples.length ~/ targetPoints);

    final List<double> rawEnvelope = [];
    double totalEnergy = 0.0;
    double maxEnergy = 0.0;

    for (int i = 0; i < samples.length; i += stepSize) {
      double sumSquares = 0.0;
      int count = 0;
      for (int w = 0; w < windowSize && (i + w) < samples.length; w++) {
        final double s = samples[i + w];
        sumSquares += s * s;
        count++;
      }
      final double rms = count > 0 ? math.sqrt(sumSquares / count) : 0.0;
      rawEnvelope.add(rms);
      totalEnergy += rms;
      if (rms > maxEnergy) maxEnergy = rms;
    }

    // 2. Normalize envelope to [0.0, 1.0]
    final double normFactor = maxEnergy > 0 ? maxEnergy : 1.0;
    final List<double> envelope = rawEnvelope.map((e) => (e / normFactor).clamp(0.0, 1.0)).toList();

    // 3. Peak Detection for Respiratory Rate (Breaths Per Minute)
    // Breathing rate in humans is typically 12 - 25 breaths/min (0.2 Hz to 0.42 Hz)
    final List<int> peakIndices = [];
    const double peakThreshold = 0.25;
    final int minPeakDistance = math.max(2, (envelope.length / (totalDurationSec > 0 ? totalDurationSec : 1) * 1.2).round());

    for (int i = 1; i < envelope.length - 1; i++) {
      if (envelope[i] > peakThreshold &&
          envelope[i] > envelope[i - 1] &&
          envelope[i] >= envelope[i + 1]) {
        if (peakIndices.isEmpty || (i - peakIndices.last) >= minPeakDistance) {
          peakIndices.add(i);
        }
      }
    }

    double bpm = 0.0;
    if (totalDurationSec > 3.0 && peakIndices.length >= 2) {
      final double breathsPerSec = peakIndices.length / totalDurationSec;
      bpm = (breathsPerSec * 60.0).clamp(8.0, 45.0);
    } else {
      bpm = 16.0; // standard default clinical resting rate
    }

    // 4. Estimate Signal-to-Noise Ratio (SNR)
    double sortedSumNoise = 0.0;
    final List<double> sorted = List.of(envelope)..sort();
    final int noiseSamplesCount = math.max(1, (sorted.length * 0.2).round());
    for (int i = 0; i < noiseSamplesCount; i++) {
      sortedSumNoise += sorted[i];
    }
    final double noiseFloor = sortedSumNoise / noiseSamplesCount;
    final double signalLevel = maxEnergy;
    final double snr = noiseFloor > 0 ? 20.0 * math.log(signalLevel / (noiseFloor + 1e-4)) / math.ln10 : 25.0;

    return PpgAnalysisResult(
      envelope: envelope,
      breathPeakIndices: peakIndices,
      estimatedBpm: double.parse(bpm.toStringAsFixed(1)),
      meanEnergy: rawEnvelope.isNotEmpty ? totalEnergy / rawEnvelope.length : 0.0,
      peakEnergy: maxEnergy,
      snrDb: double.parse(snr.clamp(6.0, 45.0).toStringAsFixed(1)),
    );
  }
}
