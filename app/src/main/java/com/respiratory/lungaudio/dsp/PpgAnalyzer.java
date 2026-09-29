package com.respiratory.lungaudio.dsp;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Phonopneumogram (PPG / Acoustic Respiratory Envelope) analyzer in Java.
 * Extracts breathing cycle envelopes, tidal volume dynamics, and estimated respiratory rate.
 */
public class PpgAnalyzer {

    public static class PpgResult {
        public final double[] envelope;
        public final List<Integer> peakIndices;
        public final double estimatedBpm;
        public final double meanEnergy;
        public final double peakEnergy;
        public final double snrDb;

        public PpgResult(double[] envelope, List<Integer> peakIndices, double estimatedBpm, double meanEnergy, double peakEnergy, double snrDb) {
            this.envelope = envelope;
            this.peakIndices = peakIndices;
            this.estimatedBpm = estimatedBpm;
            this.meanEnergy = meanEnergy;
            this.peakEnergy = peakEnergy;
            this.snrDb = snrDb;
        }
    }

    public static PpgResult analyze(double[] samples, double sampleRate, int targetPoints) {
        if (samples == null || samples.length == 0) {
            return new PpgResult(new double[0], new ArrayList<>(), 0.0, 0.0, 0.0, 0.0);
        }

        double totalDurationSec = samples.length / sampleRate;
        int windowSize = Math.max(1, (int) Math.round(sampleRate * 0.1)); // 100 ms RMS window
        int stepSize = Math.max(1, samples.length / targetPoints);

        int numPoints = (samples.length + stepSize - 1) / stepSize;
        double[] rawEnvelope = new double[numPoints];
        double totalEnergy = 0.0;
        double maxEnergy = 0.0;

        for (int p = 0; p < numPoints; p++) {
            int i = p * stepSize;
            double sumSquares = 0.0;
            int count = 0;
            for (int w = 0; w < windowSize && (i + w) < samples.length; w++) {
                double s = samples[i + w];
                sumSquares += s * s;
                count++;
            }
            double rms = count > 0 ? Math.sqrt(sumSquares / count) : 0.0;
            rawEnvelope[p] = rms;
            totalEnergy += rms;
            if (rms > maxEnergy) maxEnergy = rms;
        }

        // Normalize envelope
        double normFactor = maxEnergy > 0 ? maxEnergy : 1.0;
        double[] envelope = new double[numPoints];
        for (int i = 0; i < numPoints; i++) {
            envelope[i] = Math.max(0.0, Math.min(1.0, rawEnvelope[i] / normFactor));
        }

        // Peak detection for breathing rate (BPM)
        List<Integer> peakIndices = new ArrayList<>();
        double peakThreshold = 0.25;
        int minDistance = Math.max(2, (int) Math.round((envelope.length / (totalDurationSec > 0 ? totalDurationSec : 1)) * 1.2));

        for (int i = 1; i < envelope.length - 1; i++) {
            if (envelope[i] > peakThreshold && envelope[i] > envelope[i - 1] && envelope[i] >= envelope[i + 1]) {
                if (peakIndices.isEmpty() || (i - peakIndices.get(peakIndices.size() - 1)) >= minDistance) {
                    peakIndices.add(i);
                }
            }
        }

        double bpm = 16.0;
        if (totalDurationSec > 3.0 && peakIndices.size() >= 2) {
            double breathsPerSec = (double) peakIndices.size() / totalDurationSec;
            bpm = Math.max(8.0, Math.min(45.0, breathsPerSec * 60.0));
        }

        // Estimate SNR
        double[] sorted = Arrays.copyOf(envelope, envelope.length);
        Arrays.sort(sorted);
        int noiseCount = Math.max(1, (int) Math.round(sorted.length * 0.2));
        double noiseSum = 0.0;
        for (int i = 0; i < noiseCount; i++) noiseSum += sorted[i];
        double noiseFloor = noiseSum / noiseCount;
        double snr = noiseFloor > 0 ? 20.0 * Math.log10(maxEnergy / (noiseFloor + 1e-4)) : 25.0;

        return new PpgResult(
                envelope,
                peakIndices,
                Math.round(bpm * 10.0) / 10.0,
                numPoints > 0 ? totalEnergy / numPoints : 0.0,
                maxEnergy,
                Math.max(6.0, Math.min(45.0, Math.round(snr * 10.0) / 10.0))
        );
    }
}
