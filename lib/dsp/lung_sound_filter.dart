import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/wav_utils.dart';
import 'biquad_filter.dart';

/// Digital Signal Processor for Respiratory Lung Sounds in Dart.
///
/// Features:
/// 1. Cascaded 2nd-order 50 Hz HPF + 2000 Hz LPF Butterworth Band-Pass
///    (attenuates cardiac rumble <50 Hz and high-frequency noise >2000 Hz).
/// 2. User-configurable Acoustic Makeup Gain (+0 dB to +30 dB, default +18 dB).
/// 3. Hyperbolic tangent (tanh) soft-saturation limiter to ensure maximum loudness
///    with zero harsh digital clipping.
class LungSoundFilter {
  static const double hpfCutoffHz = 50.0;
  static const double lpfCutoffHz = 2000.0;
  static const double defaultGainDb = 18.0;

  /// Filters and amplifies a raw 16-bit PCM WAV file.
  static Future<void> processWav({
    required File inputFile,
    required File outputFile,
    double gainDb = defaultGainDb,
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

    // Initialize cascaded biquads
    final BiquadFilter hpf = BiquadFilter(
      type: FilterType.highPass,
      cutoffFreq: hpfCutoffHz,
      sampleRate: sampleRate.toDouble(),
    );
    final BiquadFilter lpf = BiquadFilter(
      type: FilterType.lowPass,
      cutoffFreq: lpfCutoffHz,
      sampleRate: sampleRate.toDouble(),
    );

    // Compute linear gain factor G = 10^(gainDb / 20)
    final double linearGain = math.pow(10.0, gainDb / 20.0).toDouble();

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final RandomAccessFile inRaf = await inputFile.open(mode: FileMode.read);
    final RandomAccessFile outRaf = await outputFile.open(mode: FileMode.write);

    try {
      // Skip input 44-byte WAV header
      await inRaf.setPosition(WavUtils.wavHeaderSize);

      // Write placeholder 44-byte WAV header to output
      final Uint8List initialHeader = WavUtils.createWavHeader(
        sampleRate: sampleRate,
        numChannels: numChannels,
        bitsPerSample: 16,
        pcmDataSize: 0,
      );
      await outRaf.writeFrom(initialHeader);

      const int chunkSize = 4096;
      final Uint8List readBuffer = Uint8List(chunkSize);
      final Uint8List writeBuffer = Uint8List(chunkSize);
      final ByteData inBd = ByteData.sublistView(readBuffer);
      final ByteData outBd = ByteData.sublistView(writeBuffer);

      int totalBytesProcessed = 0;
      int bytesRead;

      while ((bytesRead = await inRaf.readInto(readBuffer)) > 0) {
        final int samples = bytesRead ~/ 2;

        for (int i = 0; i < samples; i++) {
          final int byteOffset = i * 2;
          final int pcm16 = inBd.getInt16(byteOffset, Endian.little);
          final double normalized = pcm16 / 32768.0;

          // 1. Cascaded Butterworth Band-Pass (50 Hz HPF -> 2000 Hz LPF)
          final double step1 = hpf.process(normalized);
          final double filtered = lpf.process(step1);

          // 2. Acoustic Amplification / Makeup Gain
          final double amplified = filtered * linearGain;

          // 3. Hyperbolic Tangent (tanh) Soft Saturation Limiter
          // For quiet murmurs: tanh(u) ≈ u (transparent, distortion-free gain)
          // For loud coughs/shocks: smoothly limits asymptotically to [-1.0, 1.0]
          final double limited = math.tanh(amplified);

          final int outPcm = (limited * 32767.0).round().clamp(-32768, 32767);
          outBd.setInt16(byteOffset, outPcm, Endian.little);
        }

        await outRaf.writeFrom(writeBuffer, 0, bytesRead);
        totalBytesProcessed += bytesRead;

        if (onProgress != null && totalPcmBytes > 0) {
          final double progress = (totalBytesProcessed / totalPcmBytes).clamp(0.0, 1.0);
          onProgress(progress);
        }
      }
    } finally {
      await inRaf.close();
      await outRaf.close();
    }

    // Finalize canonical 44-byte WAV header
    final int outLength = await outputFile.length();
    final int pcmSize = outLength - WavUtils.wavHeaderSize;
    await WavUtils.updateWavSizes(outputFile, pcmSize);
  }
}
