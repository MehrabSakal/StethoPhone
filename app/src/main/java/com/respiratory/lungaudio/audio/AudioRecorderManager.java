package com.respiratory.lungaudio.audio;

import android.annotation.SuppressLint;
import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.audiofx.AcousticEchoCanceler;
import android.media.audiofx.AutomaticGainControl;
import android.media.audiofx.NoiseSuppressor;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.util.Log;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.RandomAccessFile;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Threaded AudioRecord manager strictly engineered for raw acoustic lung sound acquisition.
 *
 * Guarantees:
 * 1. AudioSource is locked to UNPROCESSED (fallback: VOICE_RECOGNITION). Never uses default MIC.
 * 2. Hardware level software pre-processing (AGC, AEC, NS) is explicitly bypassed/disabled.
 * 3. Locks sampling rate to the exact native hardware rate of the USB-C DAC/ADC to prevent resampling.
 * 4. Preferred audio routing set to external USB-C input if connected.
 * 5. Saves stream directly to a canonical 44-byte RIFF/WAVE file containing bit-perfect raw PCM data.
 */
public class AudioRecorderManager {

    private static final String TAG = "AudioRecorderManager";

    public interface RecordingCallback {
        void onRecordingStarted(int sampleRate, String sourceName);
        void onAudioLevelUpdate(double dbLevel, int progress);
        void onRecordingProgress(long elapsedMillis);
        void onRecordingStopped(File wavFile, long durationMillis);
        void onRecordingError(String message, Exception e);
    }

    private final Context context;
    private final UsbAudioHelper usbAudioHelper;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private AudioRecord audioRecord;
    private Thread recordingThread;
    private final AtomicBoolean isRecording = new AtomicBoolean(false);

    // Audio effects handles to explicitly disable
    private AutomaticGainControl agcEffect;
    private AcousticEchoCanceler aecEffect;
    private NoiseSuppressor nsEffect;

    private int lockedSampleRate = 48000;
    private File currentOutputFile;
    private long recordingStartTime = 0;

    public AudioRecorderManager(Context context, UsbAudioHelper usbAudioHelper) {
        this.context = context.getApplicationContext();
        this.usbAudioHelper = usbAudioHelper;
    }

    public boolean isRecording() {
        return isRecording.get();
    }

    public int getLockedSampleRate() {
        return lockedSampleRate;
    }

    /**
     * Starts audio recording on a dedicated high-priority audio thread.
     */
    @SuppressLint("MissingPermission")
    public synchronized void startRecording(File outputFile, RecordingCallback callback) {
        if (isRecording.get()) {
            Log.w(TAG, "Recording already in progress.");
            return;
        }

        this.currentOutputFile = outputFile;

        // 1. Inspect hardware and lock to native sample rate
        UsbAudioHelper.DeviceInfo deviceInfo = usbAudioHelper.getOptimalInputDeviceInfo();
        this.lockedSampleRate = deviceInfo.sampleRate;

        // 2. Select Audio Source: UNPROCESSED with VOICE_RECOGNITION fallback. Never MIC.
        int audioSource = MediaRecorder.AudioSource.UNPROCESSED;
        String sourceName = "UNPROCESSED (Raw Acoustic Data)";

        int channelConfig = AudioFormat.CHANNEL_IN_MONO;
        int audioEncoding = AudioFormat.ENCODING_PCM_16BIT;

        int minBufferSize = AudioRecord.getMinBufferSize(lockedSampleRate, channelConfig, audioEncoding);
        if (minBufferSize <= 0) {
            // Fallback sample rate if device driver rejects
            Log.w(TAG, "Buffer size invalid for rate " + lockedSampleRate + ", fallback to 44100");
            lockedSampleRate = 44100;
            minBufferSize = AudioRecord.getMinBufferSize(lockedSampleRate, channelConfig, audioEncoding);
        }

        // Double buffer size for jitter tolerance in USB streaming
        int bufferSize = Math.max(minBufferSize * 2, 4096);

        try {
            audioRecord = createAudioRecord(audioSource, lockedSampleRate, channelConfig, audioEncoding, bufferSize);
        } catch (Exception e) {
            Log.w(TAG, "AudioSource.UNPROCESSED not supported by HAL, falling back to VOICE_RECOGNITION", e);
            audioSource = MediaRecorder.AudioSource.VOICE_RECOGNITION;
            sourceName = "VOICE_RECOGNITION (Tuned Raw Fallback)";
            try {
                audioRecord = createAudioRecord(audioSource, lockedSampleRate, channelConfig, audioEncoding, bufferSize);
            } catch (Exception ex) {
                if (callback != null) {
                    callback.onRecordingError("Failed to initialize AudioRecord: " + ex.getMessage(), ex);
                }
                return;
            }
        }

        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            if (callback != null) {
                callback.onRecordingError("AudioRecord initialization failed (STATE_UNINITIALIZED).", null);
            }
            releaseAudioRecord();
            return;
        }

        // 3. Lock preferred device to USB-C audio device if present
        if (deviceInfo.isUsb && deviceInfo.audioDeviceInfo != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            boolean routeSuccess = audioRecord.setPreferredDevice(deviceInfo.audioDeviceInfo);
            Log.d(TAG, "Preferred device set to USB: " + routeSuccess);
        }

        // 4. Explicitly bypass / disable software AGC, AEC, NS
        disableSoftwareAudioEffects(audioRecord.getAudioSessionId());

        // 5. Start audio capture and launch dedicated worker thread
        try {
            audioRecord.startRecording();
        } catch (IllegalStateException e) {
            if (callback != null) {
                callback.onRecordingError("AudioRecord.startRecording() failed: " + e.getMessage(), e);
            }
            releaseAudioRecord();
            return;
        }

        isRecording.set(true);
        recordingStartTime = System.currentTimeMillis();

        if (callback != null) {
            final String finalSourceName = sourceName;
            mainHandler.post(() -> callback.onRecordingStarted(lockedSampleRate, finalSourceName));
        }

        recordingThread = new Thread(() -> recordAudioLoop(bufferSize, callback), "LungAudioRecordThread");
        recordingThread.start();
    }

    @SuppressLint("MissingPermission")
    private AudioRecord createAudioRecord(int source, int sampleRate, int channelConfig, int encoding, int bufferSize) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioFormat format = new AudioFormat.Builder()
                    .setEncoding(encoding)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .build();

            return new AudioRecord.Builder()
                    .setAudioSource(source)
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(bufferSize)
                    .build();
        } else {
            return new AudioRecord(source, sampleRate, channelConfig, encoding, bufferSize);
        }
    }

    /**
     * Explicitly disables Automatic Gain Control, Acoustic Echo Cancellation,
     * and Noise Suppression to ensure unaltered raw acoustics.
     */
    private void disableSoftwareAudioEffects(int audioSessionId) {
        try {
            if (AutomaticGainControl.isAvailable()) {
                agcEffect = AutomaticGainControl.create(audioSessionId);
                if (agcEffect != null) {
                    agcEffect.setEnabled(false);
                    Log.d(TAG, "Explicitly disabled AutomaticGainControl");
                }
            }
            if (AcousticEchoCanceler.isAvailable()) {
                aecEffect = AcousticEchoCanceler.create(audioSessionId);
                if (aecEffect != null) {
                    aecEffect.setEnabled(false);
                    Log.d(TAG, "Explicitly disabled AcousticEchoCanceler");
                }
            }
            if (NoiseSuppressor.isAvailable()) {
                nsEffect = NoiseSuppressor.create(audioSessionId);
                if (nsEffect != null) {
                    nsEffect.setEnabled(false);
                    Log.d(TAG, "Explicitly disabled NoiseSuppressor");
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Exception while checking/disabling audio effects", e);
        }
    }

    /**
     * Dedicated audio recording loop running on URGENT_AUDIO priority thread.
     */
    private void recordAudioLoop(int bufferSize, RecordingCallback callback) {
        // Elevate thread priority for real-time audio acquisition to prevent buffer underrun
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO);

        byte[] audioBuffer = new byte[bufferSize];
        long totalPcmBytes = 0;

        try {
            if (currentOutputFile.exists()) {
                currentOutputFile.delete();
            }

            try (FileOutputStream fos = new FileOutputStream(currentOutputFile);
                 BufferedOutputStream bos = new BufferedOutputStream(fos, bufferSize)) {

                // Write 44-byte canonical WAV header placeholder
                WavUtils.writeWavHeader(bos, lockedSampleRate, 1, 16, 0);

                long lastUiUpdateTime = 0;

                while (isRecording.get()) {
                    int bytesRead = audioRecord.read(audioBuffer, 0, audioBuffer.length);
                    if (bytesRead > 0) {
                        bos.write(audioBuffer, 0, bytesRead);
                        totalPcmBytes += bytesRead;

                        // Calculate RMS level for UI meter (every ~60ms)
                        long now = System.currentTimeMillis();
                        if (now - lastUiUpdateTime > 60) {
                            lastUiUpdateTime = now;
                            double db = calculateRmsDb(audioBuffer, bytesRead);
                            int meterProgress = (int) Math.max(0, Math.min(100, (db + 60.0) * (100.0 / 60.0)));
                            long elapsed = now - recordingStartTime;

                            if (callback != null) {
                                mainHandler.post(() -> {
                                    callback.onAudioLevelUpdate(db, meterProgress);
                                    callback.onRecordingProgress(elapsed);
                                });
                            }
                        }
                    } else if (bytesRead < 0) {
                        Log.e(TAG, "AudioRecord read error: " + bytesRead);
                        break;
                    }
                }

                bos.flush();
            }

            // Update canonical 44-byte RIFF/WAV header with finalized PCM data size
            try (RandomAccessFile raf = new RandomAccessFile(currentOutputFile, "rw")) {
                WavUtils.updateWavSizes(raf, totalPcmBytes);
            }

            long totalDuration = System.currentTimeMillis() - recordingStartTime;

            if (callback != null) {
                mainHandler.post(() -> callback.onRecordingStopped(currentOutputFile, totalDuration));
            }

        } catch (Exception e) {
            Log.e(TAG, "Error in audio recording loop", e);
            if (callback != null) {
                mainHandler.post(() -> callback.onRecordingError("Recording stream error: " + e.getMessage(), e));
            }
        } finally {
            releaseAudioRecord();
        }
    }

    /**
     * Calculates acoustic decibel level (dBFS) from 16-bit PCM bytes.
     */
    private double calculateRmsDb(byte[] buffer, int bytesRead) {
        long sum = 0;
        int sampleCount = bytesRead / 2;
        if (sampleCount == 0) return -100.0;

        for (int i = 0; i < sampleCount; i++) {
            short sample = (short) ((buffer[i * 2] & 0xFF) | (buffer[i * 2 + 1] << 8));
            sum += (long) sample * sample;
        }

        double rms = Math.sqrt((double) sum / sampleCount);
        if (rms < 1.0) return -100.0;
        return 20.0 * Math.log10(rms / 32767.0);
    }

    /**
     * Stops the audio recording.
     */
    public synchronized void stopRecording() {
        if (!isRecording.get()) return;
        isRecording.set(false);

        if (recordingThread != null) {
            try {
                recordingThread.join(1000);
            } catch (InterruptedException ignored) {}
            recordingThread = null;
        }
    }

    private void releaseAudioRecord() {
        if (audioRecord != null) {
            try {
                if (audioRecord.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                    audioRecord.stop();
                }
            } catch (Exception ignored) {}
            try {
                audioRecord.release();
            } catch (Exception ignored) {}
            audioRecord = null;
        }

        if (agcEffect != null) {
            try { agcEffect.release(); } catch (Exception ignored) {}
            agcEffect = null;
        }
        if (aecEffect != null) {
            try { aecEffect.release(); } catch (Exception ignored) {}
            aecEffect = null;
        }
        if (nsEffect != null) {
            try { nsEffect.release(); } catch (Exception ignored) {}
            nsEffect = null;
        }
    }
}
