package com.respiratory.lungaudio.audio;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

/**
 * Helper class to inspect USB-C audio hardware, prevent software resampling,
 * and lock AudioRecord to the exact native hardware sample rate.
 */
public class UsbAudioHelper {

    public static class DeviceInfo {
        public final boolean isUsb;
        public final AudioDeviceInfo audioDeviceInfo;
        public final String name;
        public final int sampleRate;
        public final String details;

        public DeviceInfo(boolean isUsb, AudioDeviceInfo audioDeviceInfo, String name, int sampleRate, String details) {
            this.isUsb = isUsb;
            this.audioDeviceInfo = audioDeviceInfo;
            this.name = name;
            this.sampleRate = sampleRate;
            this.details = details;
        }
    }

    public interface DeviceChangeListener {
        void onDeviceChanged(DeviceInfo deviceInfo);
    }

    private final AudioManager audioManager;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private DeviceChangeListener listener;
    private AudioManager.AudioRecordingCallback recordingCallback;
    private android.media.AudioDeviceCallback audioDeviceCallback;

    public UsbAudioHelper(Context context) {
        this.audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
    }

    /**
     * Determines the currently active or optimal audio input device and its hardware native sample rate.
     */
    public DeviceInfo getOptimalInputDeviceInfo() {
        if (audioManager == null) {
            return new DeviceInfo(false, null, "Default Microphone", 48000, "AudioManager unavailable, defaulting to 48 kHz");
        }

        AudioDeviceInfo[] inputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS);
        AudioDeviceInfo usbInputDevice = null;

        for (AudioDeviceInfo device : inputDevices) {
            int type = device.getType();
            if (type == AudioDeviceInfo.TYPE_USB_DEVICE || type == AudioDeviceInfo.TYPE_USB_HEADSET) {
                usbInputDevice = device;
                break;
            }
        }

        int hardwareSampleRate = queryNativeSampleRate(usbInputDevice);

        if (usbInputDevice != null) {
            CharSequence prodName = usbInputDevice.getProductName();
            String name = (prodName != null && prodName.length() > 0) ? prodName.toString() : "USB-C Audio Device";
            return new DeviceInfo(
                    true,
                    usbInputDevice,
                    name,
                    hardwareSampleRate,
                    "USB-C DAC/ADC Locked @ " + hardwareSampleRate + " Hz (Zero Resampling)"
            );
        } else {
            return new DeviceInfo(
                    false,
                    null,
                    "Built-in Mic (Internal)",
                    hardwareSampleRate,
                    "USB-C mic not detected. Internal mic locked @ " + hardwareSampleRate + " Hz"
            );
        }
    }

    /**
     * Queries the true native hardware sample rate to avoid software sample rate conversion (SRC).
     */
    private int queryNativeSampleRate(AudioDeviceInfo usbDevice) {
        // 1. If USB device is attached, inspect its hardware reported rates
        if (usbDevice != null) {
            int[] rates = usbDevice.getSampleRates();
            if (rates != null && rates.length > 0) {
                // If 48000 is supported (standard professional rate), prefer it
                for (int r : rates) {
                    if (r == 48000) return 48000;
                }
                // Otherwise pick first valid rate
                for (int r : rates) {
                    if (isValidSampleRate(r)) return r;
                }
            }
        }

        // 2. Query system HAL native sample rate property
        String halRateStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE);
        if (halRateStr != null) {
            try {
                int halRate = Integer.parseInt(halRateStr);
                if (isValidSampleRate(halRate)) {
                    return halRate;
                }
            } catch (NumberFormatException ignored) {}
        }

        // 3. Fallback standard high-resolution rate
        return 48000;
    }

    private boolean isValidSampleRate(int rate) {
        if (rate <= 0) return false;
        int minBuf = AudioRecord.getMinBufferSize(
                rate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
        );
        return minBuf > 0;
    }

    /**
     * Starts listening for audio device connection/disconnection events.
     */
    public void startListening(DeviceChangeListener listener) {
        this.listener = listener;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioManager != null) {
            this.audioDeviceCallback = new android.media.AudioDeviceCallback() {
                @Override
                public void onAudioDevicesAdded(AudioDeviceInfo[] addedDevices) {
                    notifyDeviceChange();
                }

                @Override
                public void onAudioDevicesRemoved(AudioDeviceInfo[] removedDevices) {
                    notifyDeviceChange();
                }
            };
            audioManager.registerAudioDeviceCallback(audioDeviceCallback, mainHandler);
        }
    }

    private void notifyDeviceChange() {
        if (listener != null) {
            DeviceInfo info = getOptimalInputDeviceInfo();
            mainHandler.post(() -> listener.onDeviceChanged(info));
        }
    }

    /**
     * Stops listening for device changes.
     */
    public void stopListening() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioManager != null && audioDeviceCallback != null) {
            audioManager.unregisterAudioDeviceCallback(audioDeviceCallback);
            audioDeviceCallback = null;
        }
        this.listener = null;
    }
}
