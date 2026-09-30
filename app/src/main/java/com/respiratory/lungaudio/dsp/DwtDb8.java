package com.respiratory.lungaudio.dsp;

import java.util.Arrays;

/**
 * PASS 2: Smooth Acoustic Artifact and Transient Attenuation.
 *
 * Designed to preserve 100% of natural alveolar and bronchial airflow timbre
 * while smoothing out harsh sensor friction and physical contact clicks.
 */
public class DwtDb8 {

    /**
     * Smooths acoustic transients while keeping respiratory airflow completely smooth and un-chopped.
     *
     * @param input Filtered audio samples from Pass 1
     * @param sampleRate Sampling rate in Hz
     * @return Smooth respiratory signal with natural air flow dynamics
     */
    public static double[] separateHeartAndArtifacts(double[] input, int sampleRate) {
        if (input == null || input.length == 0) {
            return new double[0];
        }

        int n = input.length;
        double[] output = new double[n];

        // Smooth transient limiter:
        // Detects isolated sharp impulse clicks (friction on mic housing) without modifying
        // the continuous, soft, stochastic wave shapes of inhalation and exhalation.
        double meanEnergy = 0.0;
        for (double s : input) {
            meanEnergy += s * s;
        }
        meanEnergy /= n;
        double rms = Math.sqrt(meanEnergy);
        double transientCeiling = Math.max(0.40, rms * 4.5);

        for (int i = 0; i < n; i++) {
            double s = input[i];
            double abs = Math.abs(s);

            if (abs > transientCeiling) {
                // Gentle soft tanh compression for sudden mechanical shocks only
                double excess = abs - transientCeiling;
                double compressed = transientCeiling + 0.10 * Math.tanh(excess / 0.10);
                output[i] = Math.signum(s) * compressed;
            } else {
                output[i] = s;
            }
        }

        return output;
    }
}
