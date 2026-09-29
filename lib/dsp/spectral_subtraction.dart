import 'dart:math' as math;
import 'dart:typed_data';
import 'fft_utils.dart';

/// PASS 3: Stationary Noise Reduction via Spectral Subtraction in Dart.
class SpectralSubtraction {
  static const int fftSize = 1024;
  static const int hopSize = 512;
  static const double alpha = 1.75; // Over-subtraction factor
  static const double beta = 0.035; // Spectral floor factor

  static List<double> reduceStationaryNoise(List<double> input, int sampleRate) {
    if (input.length < fftSize) {
      return List<double>.from(input);
    }

    final int n = input.length;
    int noiseWindowSamples = math.min(n, (0.5 * sampleRate).round());
    if (noiseWindowSamples < fftSize) {
      noiseWindowSamples = math.min(n, fftSize * 2);
    }

    // 1. Identify 0.5s of lowest energy (silence between breaths)
    final int bestStartIndex = _findQuietestSegment(input, noiseWindowSamples);

    // Precompute Hann window
    final Float64List hann = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fftSize - 1)));
    }

    // 2. Calculate noise FFT profile P_noise(k)
    final Float64List noiseProfile = _computeNoisePowerProfile(input, bestStartIndex, noiseWindowSamples, hann);

    // 3. Spectral Subtraction with Overlap-Add
    final Float64List output = Float64List(n);
    final Float64List winSum = Float64List(n);

    final Float64List real = Float64List(fftSize);
    final Float64List imag = Float64List(fftSize);

    final int numFrames = (n - fftSize) ~/ hopSize + 1;

    for (int f = 0; f < numFrames; f++) {
      final int offset = f * hopSize;

      for (int i = 0; i < fftSize; i++) {
        real[i] = input[offset + i] * hann[i];
        imag[i] = 0.0;
      }

      FftUtils.fft(real, imag);

      for (int k = 0; k < fftSize; k++) {
        final double r = real[k];
        final double im = imag[k];
        final double power = r * r + im * im;
        final double noisePower = noiseProfile[k];

        final double cleanPower = math.max(power - alpha * noisePower, beta * noisePower);
        final double originalMag = math.sqrt(power);
        final double gain = (originalMag > 1e-12) ? math.sqrt(cleanPower) / originalMag : 0.0;

        real[k] = r * gain;
        imag[k] = im * gain;
      }

      FftUtils.ifft(real, imag);

      for (int i = 0; i < fftSize; i++) {
        final int outIdx = offset + i;
        if (outIdx < n) {
          output[outIdx] += real[i] * hann[i];
          winSum[outIdx] += hann[i] * hann[i];
        }
      }
    }

    // Normalize
    for (int i = 0; i < n; i++) {
      if (winSum[i] > 1e-4) {
        output[i] /= winSum[i];
      } else {
        output[i] = input[i];
      }
    }

    return output.toList();
  }

  static int _findQuietestSegment(List<double> signal, int windowSize) {
    final int n = signal.length;
    if (n <= windowSize) return 0;

    final int step = math.max(1, windowSize ~/ 4);
    double minEnergy = double.infinity;
    int bestStart = 0;

    for (int start = 0; start <= n - windowSize; start += step) {
      double energy = 0.0;
      for (int i = 0; i < windowSize; i++) {
        final double val = signal[start + i];
        energy += val * val;
      }
      if (energy < minEnergy) {
        minEnergy = energy;
        bestStart = start;
      }
    }
    return bestStart;
  }

  static Float64List _computeNoisePowerProfile(List<double> signal, int startIdx, int len, Float64List window) {
    final Float64List avgPower = Float64List(fftSize);
    int frames = 0;

    final Float64List real = Float64List(fftSize);
    final Float64List imag = Float64List(fftSize);

    for (int pos = startIdx; pos <= startIdx + len - fftSize; pos += hopSize) {
      for (int i = 0; i < fftSize; i++) {
        real[i] = signal[pos + i] * window[i];
        imag[i] = 0.0;
      }
      FftUtils.fft(real, imag);

      for (int k = 0; k < fftSize; k++) {
        avgPower[k] += (real[k] * real[k] + imag[k] * imag[k]);
      }
      frames++;
    }

    if (frames > 0) {
      for (int k = 0; k < fftSize; k++) {
        avgPower[k] /= frames;
      }
    } else {
      for (int k = 0; k < fftSize; k++) {
        avgPower[k] = 1e-6;
      }
    }

    return avgPower;
  }
}
