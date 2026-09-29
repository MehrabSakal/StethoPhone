package com.respiratory.lungaudio;

import android.content.Context;
import com.respiratory.lungaudio.audio.AudioRecorderManager;
import com.respiratory.lungaudio.audio.UsbAudioHelper;

import java.io.File;
import java.util.HashMap;
import java.util.Map;

/**
 * Bridge class providing MethodChannel and EventChannel communication
 * between Flutter (Dart) and the Native Android USB-C Audio Recorder engine.
 */
public class FlutterAudioBridge {

    public interface LevelSink {
        void sendLevel(double db);
    }

    private final Context context;
    private final UsbAudioHelper usbAudioHelper;
    private final AudioRecorderManager recorderManager;
    private LevelSink levelSink;

    public FlutterAudioBridge(Context context) {
        this.context = context.getApplicationContext();
        this.usbAudioHelper = new UsbAudioHelper(context);
        this.recorderManager = new AudioRecorderManager(context, usbAudioHelper);
    }

    public void setLevelSink(LevelSink sink) {
        this.levelSink = sink;
    }

    public Map<String, Object> getDeviceInfo() {
        UsbAudioHelper.DeviceInfo info = usbAudioHelper.getOptimalInputDeviceInfo();
        Map<String, Object> result = new HashMap<>();
        result.put("isUsb", info.isUsb);
        result.put("name", info.name);
        result.put("sampleRate", info.sampleRate);
        result.put("details", info.details);
        return result;
    }

    public boolean startRecording(String outputFilePath) {
        File file = new File(outputFilePath);
        recorderManager.startRecording(file, new AudioRecorderManager.RecordingCallback() {
            @Override
            public void onRecordingStarted(int sampleRate, String sourceName) {}

            @Override
            public void onAudioLevelUpdate(double dbLevel, int progress) {
                if (levelSink != null) {
                    levelSink.sendLevel(dbLevel);
                }
            }

            @Override
            public void onRecordingProgress(long elapsedMillis) {}

            @Override
            public void onRecordingStopped(File wavFile, long durationMillis) {}

            @Override
            public void onRecordingError(String message, Exception e) {}
        });
        return true;
    }

    public String stopRecording() {
        if (recorderManager.isRecording()) {
            recorderManager.stopRecording();
        }
        return "SUCCESS";
    }
}
