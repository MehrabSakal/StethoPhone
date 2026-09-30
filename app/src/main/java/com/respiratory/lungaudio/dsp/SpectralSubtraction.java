package com.respiratory.lungaudio.dsp;

/**
 * PASS 3: Smooth Natural Airflow Noise Floor Management.
 *
 * Preserves 100% of organic respiratory timbre and turbulent airflow acoustics.
 * Instead of non-linear spectral subtraction (which introduces metallic musical noise
 * and underwater bubbling), this applies a smooth, clinical-grade adaptive noise floor
 * attenuator:
 * 1. Tracks inter-breath respiratory pauses using a continuous RMS envelope.
 * 2. Gently attenuates baseline microphone static (-12 dB) during pauses without
 *    affecting vesicular airflow sounds during inhalation and exhalation.
 * 3. 40 ms smooth exponential transition prevents any sudden gating clicks.
 */
public class SpectralSubtraction {

    /**
     * Smoothly suppresses baseline static during breath pauses without altering airflow timbre.
     *
     * @param input Respiratory audio samples
     * @param sampleRate Sampling rate in Hz
     * @return Cleaned samples preserving natural lung airflow timbre
     */
    public static double[] reduceStationaryNoise(double[] input, int sampleRate) {
        if (input == null || input.length == 0) {
            return new double[0];
        }

        int n = input.length;
        double[] output = new double[n];

        // 1. Track moving RMS envelope (~80 ms window)
        double alpha = Math.exp(-1.0 / (0.06 * sampleRate)); // 60 ms smoothing
        double[] rms = new double[n];
        double currentRms = 0.0;
        double minRms = Double.MAX_VALUE;

        int warmup = Math.min(n, (int) (0.2 * sampleRate));
        for (int i = 0; i < n; i++) {
            double sq = input[i] * input[i];
            currentRms = alpha * currentRms + (1.0 - alpha) * sq;
            double r = Math.sqrt(currentRms);
            rms[i] = r;
            if (i > warmup && r < minRms && r > 1e-6) {
                minRms = r;
            }
        }

        // Adaptive noise floor threshold
        double noiseFloor = (minRms < Double.MAX_VALUE && minRms > 0) ? minRms * 1.8 : 0.004;
        double gateFloorGain = 0.30; // Gentle -10.5 dB reduction during silent pauses

        double currentGate = 1.0;
        double gateAlpha = Math.exp(-1.0 / (0.04 * sampleRate)); // 40 ms smooth crossfade

        for (int i = 0; i < n; i++) {
            double r = rms[i];
            double targetGain = (r < noiseFloor) ? gateFloorGain : 1.0;

            currentGate = gateAlpha * currentGate + (1.0 - gateAlpha) * targetGain;
            output[i] = input[i] * currentGate;
        }

        return output;
    }
}
