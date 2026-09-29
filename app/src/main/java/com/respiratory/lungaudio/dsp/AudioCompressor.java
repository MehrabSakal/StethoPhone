package com.respiratory.lungaudio.dsp;

/**
 * PASS 4: Dynamics & Amplification.
 *
 * Implements:
 * 1. Audio Dynamic Range Compressor (Ratio 4:1, Fast Attack 5ms, Medium Release 70ms, Threshold -22 dBFS).
 *    Controls loud transient spikes (coughs, microphone bumps) while boosting quiet tidal breathing.
 * 2. Uniform Makeup Gain:
 *    Elevates baseline breathing volume to make vesicular murmurs, crackles, and wheezes clearly audible.
 * 3. Hard Limiter at -0.5 dBFS (0.944 peak):
 *    Strict digital ceiling to guarantee 0.00% DAC clipping and bit-perfect playback headroom.
 */
public class AudioCompressor {

    public static final double HARD_LIMITER_CEILING = 0.944; // -0.5 dBFS headroom
    public static final double DEFAULT_THRESHOLD_DB = -22.0; // -22 dBFS threshold
    public static final double COMPRESSION_RATIO = 4.0;     // 4:1 compression ratio
    public static final double ATTACK_TIME_SEC = 0.005;     // 5 ms fast attack
    public static final double RELEASE_TIME_SEC = 0.070;    // 70 ms medium release

    /**
     * Applies dynamic compression, uniform makeup gain, and -0.5 dBFS hard limiting.
     *
     * @param input Samples from Pass 3
     * @param sampleRate Sampling rate (e.g. 48000 Hz or 44100 Hz)
     * @param requestedMakeupGain Desired amplification multiplier (e.g. 10.0, or <= 0 for auto-max)
     * @return Dynamics-controlled and amplified audio samples
     */
    public static double[] processDynamicsAndGain(double[] input, int sampleRate, double requestedMakeupGain) {
        if (input == null || input.length == 0) {
            return new double[0];
        }

        int n = input.length;
        double[] compressed = new double[n];

        // 1. Setup Compressor Time Constants
        double alphaAtt = Math.exp(-1.0 / (ATTACK_TIME_SEC * sampleRate));
        double alphaRel = Math.exp(-1.0 / (RELEASE_TIME_SEC * sampleRate));
        double env = 0.0;

        for (int i = 0; i < n; i++) {
            double absX = Math.abs(input[i]);

            // Smooth envelope follower
            if (absX > env) {
                env = alphaAtt * env + (1.0 - alphaAtt) * absX;
            } else {
                env = alphaRel * env + (1.0 - alphaRel) * absX;
            }

            // Compute dB level
            double envDb = (env > 1e-6) ? 20.0 * Math.log10(env) : -120.0;

            // 4:1 compression curve
            double gainDb = 0.0;
            if (envDb > DEFAULT_THRESHOLD_DB) {
                // Compresses by (1 - 1/ratio) = (1 - 0.25) = 0.75 above threshold
                gainDb = (DEFAULT_THRESHOLD_DB + (envDb - DEFAULT_THRESHOLD_DB) / COMPRESSION_RATIO) - envDb;
            }

            double compGain = Math.pow(10.0, gainDb / 20.0);
            compressed[i] = input[i] * compGain;
        }

        // 2. Compute Optimal Uniform Makeup Gain
        // Find maximum peak after compression
        double maxCompPeak = 0.0;
        for (double v : compressed) {
            double abs = Math.abs(v);
            if (abs > maxCompPeak) {
                maxCompPeak = abs;
            }
        }

        double maxSafeGain = (maxCompPeak > 0.0001) ? (HARD_LIMITER_CEILING / maxCompPeak) : 1.0;
        double appliedMakeupGain;
        if (requestedMakeupGain <= 0) {
            // Auto-Max mode: amplify to the maximum clean physical limit
            appliedMakeupGain = maxSafeGain;
        } else {
            // Use requested multiplier, clamped safely to avoid hard limiter oversaturation
            appliedMakeupGain = Math.min(requestedMakeupGain, maxSafeGain * 1.25);
        }

        // 3. Apply Uniform Makeup Gain & Hard Limiter at -0.5 dBFS
        double[] output = new double[n];
        for (int i = 0; i < n; i++) {
            double amplified = compressed[i] * appliedMakeupGain;

            // Hard Limiter at -0.5 dBFS (0.944 max amplitude)
            output[i] = Math.max(-HARD_LIMITER_CEILING, Math.min(HARD_LIMITER_CEILING, amplified));
        }

        return output;
    }
}
