package com.respiratory.lungaudio.dsp;

/**
 * Fast Fourier Transform (FFT) and Short-Time Fourier Transform (STFT)
 * Spectrogram extraction in Java.
 */
public class FftUtils {

    /**
     * In-place Radix-2 Decimation-in-Time Fast Fourier Transform.
     */
    public static void fft(double[] real, double[] imag) {
        int n = real.length;
        if ((n & (n - 1)) != 0) {
            throw new IllegalArgumentException("FFT length must be a power of 2, got " + n);
        }

        // Bit-reversal permutation
        int j = 0;
        for (int i = 0; i < n - 1; i++) {
            if (i < j) {
                double tr = real[i];
                double ti = imag[i];
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

        // Butterfly operations
        for (int len = 2; len <= n; len <<= 1) {
            double angle = -2.0 * Math.PI / len;
            double wlenReal = Math.cos(angle);
            double wlenImag = Math.sin(angle);

            for (int i = 0; i < n; i += len) {
                double wReal = 1.0;
                double wImag = 0.0;
                int halfLen = len >> 1;

                for (int k = 0; k < halfLen; k++) {
                    int u = i + k;
                    int v = i + k + halfLen;

                    double vReal = real[v] * wReal - imag[v] * wImag;
                    double vImag = real[v] * wImag + imag[v] * wReal;

                    real[v] = real[u] - vReal;
                    imag[v] = imag[u] - vImag;
                    real[u] = real[u] + vReal;
                    imag[u] = imag[u] + vImag;

                    double nextWReal = wReal * wlenReal - wImag * wlenImag;
                    double nextWImag = wReal * wlenImag + wImag * wlenReal;
                    wReal = nextWReal;
                    wImag = nextWImag;
                }
            }
        }
    }

    /**
     * In-place Radix-2 Inverse Fast Fourier Transform.
     */
    public static void ifft(double[] real, double[] imag) {
        int n = real.length;
        for (int i = 0; i < n; i++) {
            imag[i] = -imag[i];
        }
        fft(real, imag);
        for (int i = 0; i < n; i++) {
            real[i] /= n;
            imag[i] = -imag[i] / n;
        }
    }

    /**
     * Computes Short-Time Fourier Transform (STFT) Spectrogram matrix.
     * Returns double[numFrames][numBins] normalized in [0.0, 1.0].
     */
    public static double[][] computeSpectrogram(double[] samples, int fftSize, int hopSize, double maxFreqHz, double sampleRate) {
        if (samples == null || samples.length < fftSize) {
            return new double[0][0];
        }

        int numBins = fftSize / 2;
        double freqPerBin = sampleRate / fftSize;
        int maxBin = Math.min(numBins, (int) Math.ceil(maxFreqHz / freqPerBin));

        int numFrames = (samples.length - fftSize) / hopSize + 1;
        double[][] spectrogram = new double[numFrames][maxBin];

        // Hann window precomputation
        double[] window = new double[fftSize];
        for (int i = 0; i < fftSize; i++) {
            window[i] = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * i / (fftSize - 1)));
        }

        double[] real = new double[fftSize];
        double[] imag = new double[fftSize];

        for (int f = 0; f < numFrames; f++) {
            int offset = f * hopSize;
            for (int i = 0; i < fftSize; i++) {
                real[i] = samples[offset + i] * window[i];
                imag[i] = 0.0;
            }

            fft(real, imag);

            for (int k = 0; k < maxBin; k++) {
                double mag = Math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
                // Logarithmic dB scale normalized between -80 dB and 0 dB
                double db = 20.0 * Math.log10(mag + 1e-6);
                double norm = Math.max(0.0, Math.min(1.0, (db + 80.0) / 80.0));
                spectrogram[f][k] = norm;
            }
        }

        return spectrogram;
    }
}
