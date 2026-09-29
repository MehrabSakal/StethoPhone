package com.respiratory.lungaudio.dsp;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * PASS 2: Heart & Artifact Separation via Discrete Wavelet Transform (DWT) using Daubechies 8 (db8).
 *
 * Biomedical Rationale:
 * Daubechies 8 (db8) with 8 vanishing moments and 16 filter coefficients is the clinical gold standard
 * for lung/heart sound separation because the db8 mother wavelet profile closely mirrors the acoustic morphology
 * of S1/S2 phonocardiographic heart sound waves.
 *
 * By decomposing the audio into sub-bands and applying soft-thresholding to high-energy cardiac detail
 * and approximation coefficients, cardiac "thumps" and transient motion artifacts are suppressed
 * while preserving continuous vesicular and bronchial breath sounds.
 */
public class DwtDb8 {

    // Daubechies 8 (db8) 16-tap Low-pass Decomposition Filter coefficients (Lo_D)
    public static final double[] H = {
        -0.00011747233804595679,
         0.0006754494059985568,
        -0.001523892856294792,
        -0.0005710441908683522,
         0.010533077723530467,
        -0.03224486958450811,
        -0.03535925835929424,
         0.37740285561283066,
         0.7805187802879577,
         0.3976377417702224,
        -0.08230105910865824,
        -0.02787990694202868,
         0.03523877377013813,
        -0.004944002638848449,
        -0.0001600818227914772,
         0.0000325114055765205
    };

    private static final int FILTER_LEN = 16;
    private static final double[] G = new double[FILTER_LEN];      // Hi_D (High-pass Decomposition)
    private static final double[] H_REC = new double[FILTER_LEN];  // Lo_R (Low-pass Reconstruction)
    private static final double[] G_REC = new double[FILTER_LEN];  // Hi_R (High-pass Reconstruction)

    static {
        for (int i = 0; i < FILTER_LEN; i++) {
            // Quadrature mirror filter relations
            G[i] = ((i % 2 == 0) ? 1.0 : -1.0) * H[FILTER_LEN - 1 - i];
            H_REC[i] = H[FILTER_LEN - 1 - i];
            G_REC[i] = ((i % 2 == 0) ? -1.0 : 1.0) * H[i];
        }
    }

    /**
     * Executes the complete Pass 2 heart and artifact separation.
     * Decomposes signal with db8, soft-thresholds cardiac energy sub-bands, and reconstructs.
     *
     * @param input Raw filtered samples from Pass 1
     * @param sampleRate Sampling rate (e.g. 48000 Hz or 44100 Hz)
     * @return Cardiac-suppressed acoustic lung sound signal
     */
    public static double[] separateHeartAndArtifacts(double[] input, int sampleRate) {
        if (input == null || input.length < FILTER_LEN * 4) {
            return input != null ? input.clone() : new double[0];
        }

        int origLen = input.length;
        // Determine optimal decomposition levels (typically 5 levels for 44.1k/48k audio)
        int levels = Math.min(5, (int) (Math.log(origLen / (double) FILTER_LEN) / Math.log(2.0)));
        if (levels < 2) return input.clone();

        // 1. Forward DWT Multi-Level Decomposition
        List<double[]> detailCoeffs = new ArrayList<>();
        List<Integer> lengths = new ArrayList<>();
        double[] approx = input.clone();

        for (int l = 0; l < levels; l++) {
            lengths.add(approx.length);
            double[][] step = dwtStep(approx);
            approx = step[0];
            detailCoeffs.add(step[1]);
        }

        // 2. Soft Thresholding on High-Energy Cardiac Sub-Bands
        // At 48 kHz:
        // Level 1: 12-24 kHz (mic hiss)
        // Level 2: 6-12 kHz
        // Level 3: 3-6 kHz
        // Level 4: 1.5-3 kHz
        // Level 5: 750-1500 Hz
        // Approx: 0-750 Hz (Dominant cardiac S1/S2 thumps & heart sound fundamentals live here)
        for (int l = 0; l < detailCoeffs.size(); l++) {
            double[] d = detailCoeffs.get(l);
            // Levels 3, 4, 5 contain prominent cardiac harmonics and motion clicks
            if (l >= 2) {
                applySoftThreshold(d, 2.2);
            }
        }

        // Strongly attenuate cardiac fundamental pulses in lowest approximation band (0 - 750 Hz)
        applyCardiacSpikeAttenuation(approx);

        // 3. Inverse DWT (IDWT) Synthesis
        for (int l = levels - 1; l >= 0; l--) {
            double[] d = detailCoeffs.get(l);
            int targetLen = lengths.get(l);
            approx = idwtStep(approx, d, targetLen);
        }

        // Ensure bit-exact length match to original input
        if (approx.length > origLen) {
            return Arrays.copyOf(approx, origLen);
        } else if (approx.length < origLen) {
            double[] padded = new double[origLen];
            System.arraycopy(approx, 0, padded, 0, approx.length);
            return padded;
        }
        return approx;
    }

    /**
     * Single level forward DWT step using db8 filters with symmetric boundary reflection.
     */
    private static double[][] dwtStep(double[] x) {
        int n = x.length;
        int halfLen = (n + 1) / 2;
        double[] cA = new double[halfLen];
        double[] cD = new double[halfLen];

        for (int i = 0; i < halfLen; i++) {
            int center = i * 2;
            double sumA = 0.0;
            double sumD = 0.0;

            for (int k = 0; k < FILTER_LEN; k++) {
                int idx = center + k - (FILTER_LEN / 2);
                // Symmetric boundary extension
                if (idx < 0) idx = -idx - 1;
                else if (idx >= n) idx = 2 * n - 1 - idx;
                if (idx < 0) idx = 0;
                else if (idx >= n) idx = n - 1;

                sumA += x[idx] * H[k];
                sumD += x[idx] * G[k];
            }
            cA[i] = sumA;
            cD[i] = sumD;
        }

        return new double[][]{ cA, cD };
    }

    /**
     * Single level inverse DWT step using db8 synthesis filters.
     */
    private static double[] idwtStep(double[] cA, double[] cD, int targetLen) {
        int nA = cA.length;
        double[] out = new double[targetLen];

        int outHalf = (targetLen + 1) / 2;
        int limit = Math.min(nA, outHalf);

        for (int i = 0; i < limit; i++) {
            int center = i * 2;
            for (int k = 0; k < FILTER_LEN; k++) {
                int outIdx = center + k - (FILTER_LEN / 2);
                if (outIdx >= 0 && outIdx < targetLen) {
                    out[outIdx] += cA[i] * H_REC[k] + cD[i] * G_REC[k];
                }
            }
        }
        return out;
    }

    /**
     * Applies soft-thresholding to suppress localized high-energy cardiac burst spikes.
     */
    private static void applySoftThreshold(double[] subband, double multiplier) {
        if (subband == null || subband.length == 0) return;

        double[] absVals = new double[subband.length];
        for (int i = 0; i < subband.length; i++) absVals[i] = Math.abs(subband[i]);
        Arrays.sort(absVals);
        double median = absVals[absVals.length / 2];

        // Robust Noise floor estimate sigma = median(|x|) / 0.6745
        double sigma = median / 0.6745;
        double threshold = multiplier * sigma * Math.sqrt(2.0 * Math.log(Math.max(2, subband.length)));

        if (threshold <= 0.00001) return;

        for (int i = 0; i < subband.length; i++) {
            double v = subband[i];
            double absV = Math.abs(v);
            if (absV > threshold) {
                // Soft threshold: pulls down cardiac spikes smoothly without phase discontinuity
                subband[i] = Math.signum(v) * (absV - 0.75 * threshold);
            }
        }
    }

    /**
     * Suppresses prominent low-frequency cardiac thump pulses in the lowest approximation band.
     */
    private static void applyCardiacSpikeAttenuation(double[] approx) {
        if (approx == null || approx.length == 0) return;

        double sum = 0.0;
        for (double v : approx) sum += Math.abs(v);
        double meanAbs = sum / approx.length;
        double threshold = meanAbs * 2.8;

        for (int i = 0; i < approx.length; i++) {
            double abs = Math.abs(approx[i]);
            if (abs > threshold) {
                double excess = abs - threshold;
                // Compress cardiac thump peak smoothly
                double compressedAbs = threshold + excess * 0.25;
                approx[i] = Math.signum(approx[i]) * compressedAbs;
            }
        }
    }
}
