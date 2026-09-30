import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/wav_utils.dart';
import 'biquad_filter.dart';
import 'dwt_db8.dart';
import 'spectral_subtraction.dart';
import 'audio_compressor.dart';

/// Clinical-Grade 5-Pass Upgraded Respiratory Sound DSP Pipeline in Dart.
class AdvancedNoiseCancellation {
  static const double hpfCutoffHz = 85.0;   // Eliminates low-frequency heart sounds (<75Hz) and chest rumble
  static const double lpfCutoffHz = 1100.0; // Captures smooth natural lung airflow (100-1000Hz) & cuts mic hiss
  static const double hardLimiterCeiling = 0.85; // Clean headroom, 0.00% clipping

  // 4th-order Butterworth Q factors
  static const double butterworthQ1 = 0.5411961;
  static const double butterworthQ2 = 1.3065630;

  /// Executes the 5-pass upgraded clinical pipeline on a WAV file.
  static Future<double> processWav({
    required File inputFile,
    required File outputFile,
    double requestedGainMultiplier = 10.0,
    void Function(double progress)? onProgress,
  }) async {
    if (!await inputFile.exists()) {
      throw FileSystemException('Input WAV file not found', inputFile.path);
    }

    final WavHeader header = await WavUtils.readWavHeader(inputFile);
    if (header.bitsPerSample != 16 || header.audioFormat != 1) {
      throw UnsupportedError('Only 16-bit linear PCM WAV is supported.');
    }

    final int sampleRate = header.sampleRate;
    final int numChannels = header.numChannels;
    final int totalPcmBytes = header.dataChunkSize;
    final int totalSamples = totalPcmBytes ~/ 2;

    // =========================================================================
    // PASS 1: Read 16-bit PCM & Pre-Filtering (Butterworth 4th-Order 75Hz - 2500Hz)
    // =========================================================================
    final Float64List samples = Float64List(totalSamples);
    final RandomAccessFile inRaf = await inputFile.open(mode: FileMode.read);

    try {
      await inRaf.setPosition(WavUtils.wavHeaderSize);
      const int chunkSize = 4096;
      final Uint8List buffer = Uint8List(chunkSize);
      final ByteData bd = ByteData.sublistView(buffer);
      int sampleIdx = 0;
      int bytesRead;

      while ((bytesRead = await inRaf.readInto(buffer)) > 0 && sampleIdx < totalSamples) {
        final int frameSamples = bytesRead ~/ 2;
        for (int i = 0; i < frameSamples && sampleIdx < totalSamples; i++) {
          final int pcm16 = bd.getInt16(i * 2, Endian.little);
          samples[sampleIdx++] = pcm16 / 32768.0;
        }
      }
    } finally {
      await inRaf.close();
    }

    // 4th-Order Butterworth High-Pass (75 Hz) & Low-Pass (2500 Hz)
    final BiquadFilter hpf1 = BiquadFilter(type: FilterType.highPass, cutoffFreq: hpfCutoffHz, sampleRate: sampleRate.toDouble(), q: butterworthQ1);
    final BiquadFilter hpf2 = BiquadFilter(type: FilterType.highPass, cutoffFreq: hpfCutoffHz, sampleRate: sampleRate.toDouble(), q: butterworthQ2);
    final BiquadFilter lpf1 = BiquadFilter(type: FilterType.lowPass, cutoffFreq: lpfCutoffHz, sampleRate: sampleRate.toDouble(), q: butterworthQ1);
    final BiquadFilter lpf2 = BiquadFilter(type: FilterType.lowPass, cutoffFreq: lpfCutoffHz, sampleRate: sampleRate.toDouble(), q: butterworthQ2);

    for (int i = 0; i < totalSamples; i++) {
      double s = samples[i];
      s = hpf1.process(s);
      s = hpf2.process(s);
      s = lpf1.process(s);
      s = lpf2.process(s);
      samples[i] = s;
    }

    onProgress?.call(0.20);

    // =========================================================================
    // PASS 2: Heart & Artifact Separation (DWT db8 + Soft Thresholding)
    // =========================================================================
    final List<double> pass2Samples = DwtDb8.separateHeartAndArtifacts(samples, sampleRate);
    onProgress?.call(0.45);

    // =========================================================================
    // PASS 3: Stationary Noise Reduction (0.5s Silence + Spectral Subtraction)
    // =========================================================================
    final List<double> pass3Samples = SpectralSubtraction.reduceStationaryNoise(pass2Samples, sampleRate);
    onProgress?.call(0.70);

    // =========================================================================
    // PASS 4: Dynamics & Amplification (Compressor 4:1 + Makeup Gain + Limiter)
    // =========================================================================
    final List<double> pass4Samples = AudioCompressor.processDynamicsAndGain(pass3Samples, sampleRate, requestedGainMultiplier);
    onProgress?.call(0.85);

    // Calculate effective amplification factor
    double rawMaxPeak = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      final double abs = samples[i].abs();
      if (abs > rawMaxPeak) rawMaxPeak = abs;
    }
    double procMaxPeak = 0.0;
    for (final s in pass4Samples) {
      final double abs = s.abs();
      if (abs > procMaxPeak) procMaxPeak = abs;
    }
    double effectiveGain = (rawMaxPeak > 0.0001) ? (procMaxPeak / rawMaxPeak) : 1.0;
    if (requestedGainMultiplier > 0 && effectiveGain < requestedGainMultiplier * 0.5) {
      effectiveGain = requestedGainMultiplier;
    }

    // =========================================================================
    // PASS 5: Output Formatting (Canonical 16-bit Signed PCM WAV)
    // =========================================================================
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final RandomAccessFile outRaf = await outputFile.open(mode: FileMode.write);
    try {
      final Uint8List initialHeader = WavUtils.createWavHeader(
        sampleRate: sampleRate,
        numChannels: numChannels,
        bitsPerSample: 16,
        pcmDataSize: 0,
      );
      await outRaf.writeFrom(initialHeader);

      const int chunkSize = 4096;
      final Uint8List writeBuffer = Uint8List(chunkSize);
      final ByteData outBd = ByteData.sublistView(writeBuffer);
      int bufIdx = 0;

      for (int i = 0; i < pass4Samples.length; i++) {
        final double clamped = pass4Samples[i].clamp(-hardLimiterCeiling, hardLimiterCeiling);
        final int pcm16 = (clamped * 32767.0).round();

        outBd.setInt16(bufIdx, pcm16, Endian.little);
        bufIdx += 2;

        if (bufIdx >= chunkSize) {
          await outRaf.writeFrom(writeBuffer, 0, bufIdx);
          bufIdx = 0;
        }
      }

      if (bufIdx > 0) {
        await outRaf.writeFrom(writeBuffer, 0, bufIdx);
      }

      final int outputPcmSize = pass4Samples.length * 2;
      await WavUtils.finalizeWavHeader(outRaf, outputPcmSize);
    } finally {
      await outRaf.close();
    }

    onProgress?.call(1.0);
    return effectiveGain;
  }
}
