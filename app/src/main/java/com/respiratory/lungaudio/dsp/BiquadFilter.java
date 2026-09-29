package com.respiratory.lungaudio.dsp;

/**
 * High-precision Second-Order Infinite Impulse Response (IIR) Biquad Filter.
 *
 * Implements standard Direct Form II Transposed equations derived from the
 * Robert Bristow-Johnson (RBJ) Audio EQ Cookbook for maximal numerical stability
 * and minimal quantization noise.
 *
 * Transfer function:
 * H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
 */
public class BiquadFilter {

    public enum Type {
        HIGH_PASS,
        LOW_PASS
    }

    // Normalized coefficients
    private double b0, b1, b2;
    private double a1, a2;

    // Filter state delay registers (Direct Form II Transposed)
    private double z1 = 0.0;
    private double z2 = 0.0;

    /**
     * Constructs and initializes a Butterworth biquad filter.
     * For Butterworth maximally flat magnitude response, Q = 1 / sqrt(2) ≈ 0.70710678.
     *
     * @param type       Filter type (HIGH_PASS or LOW_PASS)
     * @param cutoffFreq Cutoff frequency in Hertz (e.g., 50.0 for HPF, 2000.0 for LPF)
     * @param sampleRate Hardware sampling rate in Hertz (e.g., 44100.0 or 48000.0)
     */
    public BiquadFilter(Type type, double cutoffFreq, double sampleRate) {
        configure(type, cutoffFreq, 1.0 / Math.sqrt(2.0), sampleRate);
    }

    public BiquadFilter(Type type, double cutoffFreq, double q, double sampleRate) {
        configure(type, cutoffFreq, q, sampleRate);
    }

    public void configureButterworth(Type type, double cutoffFreq, double sampleRate) {
        configure(type, cutoffFreq, 1.0 / Math.sqrt(2.0), sampleRate);
    }

    /**
     * Calculates the normalized biquad coefficients for specified cutoff and Q-factor.
     */
    public void configure(Type type, double cutoffFreq, double q, double sampleRate) {
        // Clamp cutoff to strictly below Nyquist frequency (sampleRate / 2)
        double nyquist = sampleRate / 2.0;
        double fc = Math.min(cutoffFreq, nyquist * 0.99);
        fc = Math.max(fc, 1.0); // Keep above DC

        double omega0 = 2.0 * Math.PI * fc / sampleRate;
        double alpha = Math.sin(omega0) / (2.0 * q);
        double cosOmega0 = Math.cos(omega0);

        double rawB0, rawB1, rawB2;
        double rawA0, rawA1, rawA2;

        if (type == Type.LOW_PASS) {
            // Low-Pass Filter formulation
            rawB0 = (1.0 - cosOmega0) / 2.0;
            rawB1 = 1.0 - cosOmega0;
            rawB2 = (1.0 - cosOmega0) / 2.0;
            rawA0 = 1.0 + alpha;
            rawA1 = -2.0 * cosOmega0;
            rawA2 = 1.0 - alpha;
        } else {
            // High-Pass Filter formulation
            rawB0 = (1.0 + cosOmega0) / 2.0;
            rawB1 = -(1.0 + cosOmega0);
            rawB2 = (1.0 + cosOmega0) / 2.0;
            rawA0 = 1.0 + alpha;
            rawA1 = -2.0 * cosOmega0;
            rawA2 = 1.0 - alpha;
        }

        // Normalize all coefficients by a0
        this.b0 = rawB0 / rawA0;
        this.b1 = rawB1 / rawA0;
        this.b2 = rawB2 / rawA0;
        this.a1 = rawA1 / rawA0;
        this.a2 = rawA2 / rawA0;

        resetState();
    }

    /**
     * Resets the filter internal delay registers to zero.
     */
    public void resetState() {
        this.z1 = 0.0;
        this.z2 = 0.0;
    }

    /**
     * Processes a single input sample x[n] and produces output sample y[n]
     * using Direct Form II Transposed topology:
     *
     * y[n] = b0 * x[n] + z1
     * z1   = b1 * x[n] - a1 * y[n] + z2
     * z2   = b2 * x[n] - a2 * y[n]
     *
     * @param x Input sample normalized to [-1.0, 1.0]
     * @return Filtered output sample
     */
    public double process(double x) {
        double y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return y;
    }
}
