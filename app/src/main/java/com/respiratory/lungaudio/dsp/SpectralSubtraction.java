package com.respiratory.lungaudio.dsp;

import java.util.Arrays;

/**
 * PASS 3: Stationary Noise Reduction via Spectral Subtraction.
 *
 * Clinical & Acoustic Rationale:
 * 1. Automatic Inter-Breath Silence Detection:
 *    Scans the recording to identify a 0.5-second quiescent period (the natural end-expiratory pause)
 *    where lung airflow ceases, isolating the true baseline microphone thermal noise and ambient acoustic static.
 * 2. Noise FFT Profile Extraction:
 *    Averages power spectra across the 0.5s silence window to form a stationary noise model P_noise(f).
 * 3. Non-Linear Spectral Subtraction with Musical Noise Mitigation:
 *    Subtracts alpha * P_noise(f) with an over-subtraction factor (alpha ≈ 1.8) and a safety spectral floor
 *    (beta ≈ 0.04) to eliminate baseline static while preserving subtle wheezes and vesicular murmurs.
 * 4. Phase-Preserving Overlap-Add (OLA) Reconstruction:
 *    Reconstructs the time-domain signal using original phase, ensuring 100% natural acoustic dynamics.
 */
public class SpectralSubtraction {

    private static final int FFT_SIZE = 1024;
    private static final int HOP_SIZE = 512;
    private static final double ALPHA = 1.75; // Over-subtraction factor
    private static final double BETA = 0.035; // Spectral floor factor to prevent musical noise

    /**
     * Performs Pass 3 stationary noise reduction on audio samples.
     *
     * @param input Samples from Pass 2
     * @param sampleRate Sampling rate (e.g. 48000 Hz or 44100 Hz)
     * @return Cleaned samples with baseline mic static removed
     */
    public static double[] reduceStationaryNoise(double[] input, int sampleRate) {
        if (input == null || input.length < FFT_SIZE) {
            return input != null ? input.clone() : new double[0];
        }

        int n = input.length;
        int noiseWindowSamples = Math.min(n, (int) (0.5 * sampleRate));
        if (noiseWindowSamples < FFT_SIZE) {
            noiseWindowSamples = Math.min(n, FFT_SIZE * 2);
        }

        // 1. Identify 0.5s of lowest energy (silence between breaths)
        int bestStartIndex = findQuietestSegment(input, noiseWindowSamples);

        // Precompute Hann window
        double[] hann = new double[FFT_SIZE];
        for (int i = 0; i < FFT_SIZE; i++) {
            hann[i] = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * i / (FFT_SIZE - 1)));
        }

        // 2. Calculate noise FFT power profile P_noise(k)
        double[] noiseProfile = computeNoisePowerProfile(input, bestStartIndex, noiseWindowSamples, hann);

        // 3. Apply Spectral Subtraction frame-by-frame with Overlap-Add
        double[] output = new double[n];
        double[] winSum = new double[n];

        double[] real = new double[FFT_SIZE];
        double[] imag = new double[FFT_SIZE];

        int numFrames = (n - FFT_SIZE) / HOP_SIZE + 1;

        for (int f = 0; f < numFrames; f++) {
            int offset = f * HOP_SIZE;

            // Windowed frame
            for (int i = 0; i < FFT_SIZE; i++) {
                real[i] = input[offset + i] * hann[i];
                imag[i] = 0.0;
            }

            // FFT
            FftUtils.fft(real, imag);

            // Spectral subtraction on magnitude
            for (int k = 0; k < FFT_SIZE; k++) {
                double r = real[k];
                double im = imag[k];
                double power = r * r + im * im;
                double noisePower = noiseProfile[k];

                // Subtracted power with spectral floor
                double cleanPower = Math.max(power - ALPHA * noisePower, BETA * noisePower);
                double originalMag = Math.sqrt(power);
                double gain = (originalMag > 1e-12) ? Math.sqrt(cleanPower) / originalMag : 0.0;

                real[k] = r * gain;
                imag[k] = im * gain;
            }

            // IFFT
            FftUtils.ifft(real, imag);

            // Overlap-Add with synthesis window
            for (int i = 0; i < FFT_SIZE; i++) {
                int outIdx = offset + i;
                if (outIdx < n) {
                    output[outIdx] += real[i] * hann[i];
                    winSum[outIdx] += hann[i] * hann[i];
                }
            }
        }

        // 4. Normalize by synthesis window overlap sum
        for (int i = 0; i < n; i++) {
            if (winSum[i] > 1e-4) {
                output[i] /= winSum[i];
            } else {
                output[i] = input[i]; // Fallback for boundary edges
            }
        }

        return output;
    }

    /**
     * Finds the starting index of the quietest 0.5s segment (inter-breath interval).
     */
    private static int findQuietestSegment(double[] signal, int windowSize) {
        int n = signal.length;
        if (n <= windowSize) return 0;

        int step = Math.max(1, windowSize / 4);
        double minEnergy = Double.MAX_VALUE;
        int bestStart = 0;

        for (int start = 0; start <= n - windowSize; start += step) {
            double energy = 0.0;
            for (int i = 0; i < windowSize; i++) {
                double val = signal[start + i];
                energy += val * val;
            }
            if (energy < minEnergy) {
                minEnergy = energy;
                bestStart = start;
            }
        }
        return bestStart;
    }

    /**
     * Calculates the average noise power spectrum P_noise[k] from the quietest segment.
     */
    private static double[] computeNoisePowerProfile(double[] signal, int startIdx, int len, double[] window) {
        double[] avgPower = new double[FFT_SIZE];
        int frames = 0;

        double[] real = new double[FFT_SIZE];
        double[] imag = new double[FFT_SIZE];

        for (int pos = startIdx; pos <= startIdx + len - FFT_SIZE; pos += HOP_SIZE) {
            for (int i = 0; i < FFT_SIZE; i++) {
                real[i] = signal[pos + i] * window[i];
                imag[i] = 0.0;
            }
            FftUtils.fft(real, imag);

            for (int k = 0; k < FFT_SIZE; k++) {
                avgPower[k] += (real[k] * real[k] + imag[k] * imag[k]);
            }
            frames++;
        }

        if (frames > 0) {
            for (int k = 0; k < FFT_SIZE; k++) {
                avgPower[k] /= frames;
            }
        } else {
            // Default tiny floor if segment was too small
            Arrays.fill(avgPower, 1e-6);
        }

        return avgPower;
    }
}
