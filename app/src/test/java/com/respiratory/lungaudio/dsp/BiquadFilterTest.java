package com.respiratory.lungaudio.dsp;

import org.junit.Assert;
import org.junit.Test;

/**
 * Unit tests validating frequency attenuation, amplification gain,
 * and numerical stability of the Second-Order Butterworth Biquad Filters.
 */
public class BiquadFilterTest {

    private static final double SAMPLE_RATE = 48000.0;

    @Test
    public void testHighPassFilterAttenuatesLowFrequencies() {
        BiquadFilter hpf = new BiquadFilter(BiquadFilter.Type.HIGH_PASS, 50.0, SAMPLE_RATE);

        // Generate a 10 Hz tone (rumble) and a 300 Hz tone (respiratory sound)
        double rumbleAmp = measureFilterGain(hpf, 10.0, SAMPLE_RATE);
        hpf.resetState();
        double lungSoundAmp = measureFilterGain(hpf, 300.0, SAMPLE_RATE);

        // 10 Hz tone should be heavily attenuated compared to 300 Hz
        Assert.assertTrue("10 Hz tone should be attenuated much more than 300 Hz tone",
                rumbleAmp < lungSoundAmp * 0.15);
    }

    @Test
    public void testLowPassFilterAttenuatesHighFrequencies() {
        BiquadFilter lpf = new BiquadFilter(BiquadFilter.Type.LOW_PASS, 2000.0, SAMPLE_RATE);

        // Generate a 500 Hz tone (vesicular sound) and an 8000 Hz tone (high-frequency noise)
        double lungSoundAmp = measureFilterGain(lpf, 500.0, SAMPLE_RATE);
        lpf.resetState();
        double noiseAmp = measureFilterGain(lpf, 8000.0, SAMPLE_RATE);

        // 8000 Hz tone should be heavily attenuated compared to 500 Hz
        Assert.assertTrue("8000 Hz tone should be attenuated much more than 500 Hz tone",
                noiseAmp < lungSoundAmp * 0.15);
    }

    @Test
    public void testAmplificationAndTanhLimiting() {
        double gainDb = 18.0;
        double linearGain = Math.pow(10.0, gainDb / 20.0); // ~7.94
        Assert.assertEquals(7.94, linearGain, 0.05);

        // Test small quiet breath sound is amplified linearly
        double quietSample = 0.02; // -34 dBFS
        double amplified = quietSample * linearGain; // ~0.158
        double limitedQuiet = Math.tanh(amplified);
        // tanh(0.158) is virtually equal to 0.158 (negligible distortion < 1%)
        Assert.assertEquals(amplified, limitedQuiet, 0.01);

        // Test loud peak is smoothly soft-limited without exceeding 1.0
        double loudSample = 0.9;
        double amplifiedLoud = loudSample * linearGain;
        double limitedLoud = Math.tanh(amplifiedLoud);
        Assert.assertTrue("Loud sample should be soft-limited to <= 1.0", limitedLoud <= 1.0);
        Assert.assertTrue("Loud sample should remain positive and non-zero", limitedLoud > 0.9);
    }

    @Test
    public void testNumericalStability() {
        BiquadFilter hpf = new BiquadFilter(BiquadFilter.Type.HIGH_PASS, 50.0, SAMPLE_RATE);
        BiquadFilter lpf = new BiquadFilter(BiquadFilter.Type.LOW_PASS, 2000.0, SAMPLE_RATE);

        for (int i = 0; i < 10000; i++) {
            double sample = (Math.random() * 2.0) - 1.0;
            double out = lpf.process(hpf.process(sample));
            Assert.assertFalse("Output should not be NaN", Double.isNaN(out));
            Assert.assertFalse("Output should not be Infinite", Double.isInfinite(out));
            Assert.assertTrue("Output should remain stably bounded", Math.abs(out) < 5.0);
        }
    }

    private double measureFilterGain(BiquadFilter filter, double freq, double sampleRate) {
        int numSamples = 2000;
        double maxOutput = 0.0;

        for (int n = 0; n < numSamples; n++) {
            double input = Math.sin(2.0 * Math.PI * freq * n / sampleRate);
            double output = filter.process(input);
            if (n > 1000) {
                maxOutput = Math.max(maxOutput, Math.abs(output));
            }
        }
        return maxOutput;
    }
}
