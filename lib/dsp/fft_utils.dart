import 'dart:math' as math;

/// Fast Fourier Transform and Spectrogram (STFT) extraction utilities in Dart.
class FftUtils {
  /// Computes in-place Radix-2 Decimation-In-Time Fast Fourier Transform.
  /// Input real and imag arrays must have length equal to a power of 2.
  static void fft(List<double> real, List<double> imag) {
    final int n = real.length;
    if ((n & (n - 1)) != 0) {
      throw ArgumentError('FFT length must be a power of 2, got $n');
    }

    // Bit-reversal permutation
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (i < j) {
        final double tr = real[i];
        final double ti = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = tr;
        imag[j] = ti;
      }
      int k = n >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }

    // Butterfly computations
    for (int len = 2; len <= n; len <<= 1) {
      final double angle = -2.0 * math.pi / len;
      final double wlenReal = math.cos(angle);
      final double wlenImag = math.sin(angle);

      for (int i = 0; i < n; i += len) {
        double wReal = 1.0;
        double wImag = 0.0;
        final int halfLen = len >> 1;

        for (int k = 0; k < halfLen; k++) {
          final int u = i + k;
          final int v = i + k + halfLen;

          final double vReal = real[v] * wReal - imag[v] * wImag;
          final double vImag = real[v] * wImag + imag[v] * wReal;

          real[v] = real[u] - vReal;
          imag[v] = imag[u] - vImag;
          real[u] = real[u] + vReal;
          imag[u] = imag[u] + vImag;

          final double nextWReal = wReal * wlenReal - wImag * wlenImag;
          final double nextWImag = wReal * wlenImag + wImag * wlenReal;
          wReal = nextWReal;
          wImag = nextWImag;
        }
      }
    }
  }

  /// In-place Radix-2 Inverse Fast Fourier Transform.
  static void ifft(Float64List real, Float64List imag) {
    final int n = real.length;
    for (int i = 0; i < n; i++) {
      imag[i] = -imag[i];
    }
    fft(real, imag);
    for (int i = 0; i < n; i++) {
      real[i] /= n;
      imag[i] = -imag[i] / n;
    }
  }

  /// Computes Short-Time Fourier Transform (STFT) Spectrogram from normalized audio samples.
  /// Returns a 2D list of normalized magnitudes [timeFrame][frequencyBin].
  static List<List<double>> computeSpectrogram({
    required List<double> samples,
    int fftSize = 256,
    int hopSize = 128,
    double maxFreqHz = 2500.0,
    double sampleRate = 48000.0,
  }) {
    final List<List<double>> spectrogram = [];
    if (samples.length < fftSize) return spectrogram;

    final int numBins = fftSize ~/ 2;
    final double freqPerBin = sampleRate / fftSize;
    final int maxBin = math.min(numBins, (maxFreqHz / freqPerBin).ceil());

    // Precompute Hann window
    final List<double> window = List.generate(
      fftSize,
      (i) => 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fftSize - 1))),
    );

    final List<double> real = List.filled(fftSize, 0.0);
    final List<double> imag = List.filled(fftSize, 0.0);

    for (int offset = 0; offset + fftSize <= samples.length; offset += hopSize) {
      for (int i = 0; i < fftSize; i++) {
        real[i] = samples[offset + i] * window[i];
        imag[i] = 0.0;
      }

      fft(real, imag);

      final List<double> spectrum = List.filled(maxBin, 0.0);
      for (int k = 0; k < maxBin; k++) {
        final double magnitude = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
        // Convert to dB scale with floor at -80 dB
        final double db = 20.0 * math.log(magnitude + 1e-6) / math.ln10;
        final double norm = ((db + 80.0) / 80.0).clamp(0.0, 1.0);
        spectrum[k] = norm;
      }
      spectrogram.add(spectrum);
    }

    return spectrogram;
  }
}
