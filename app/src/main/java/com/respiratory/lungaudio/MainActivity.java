package com.respiratory.lungaudio;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.respiratory.lungaudio.adapter.RecordingsAdapter;
import com.respiratory.lungaudio.audio.AudioPlayerManager;
import com.respiratory.lungaudio.audio.AudioRecorderManager;
import com.respiratory.lungaudio.audio.UsbAudioHelper;
import com.respiratory.lungaudio.audio.WavUtils;
import com.respiratory.lungaudio.databinding.ActivityMainBinding;
import com.respiratory.lungaudio.model.RecordingItem;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public class MainActivity extends AppCompatActivity {

    private ActivityMainBinding binding;

    private UsbAudioHelper usbAudioHelper;
    private AudioRecorderManager recorderManager;
    private AudioPlayerManager audioPlayer;

    private UsbAudioHelper.DeviceInfo currentDeviceInfo;
    private File rawWavFile;

    // Timer & live dB update
    private final Handler timerHandler = new Handler(Looper.getMainLooper());
    private long recordingStartTime = 0;
    private final Runnable timerRunnable = new Runnable() {
        @Override
        public void run() {
            if (recorderManager != null && recorderManager.isRecording()) {
                long elapsed = System.currentTimeMillis() - recordingStartTime;
                long totalSec = elapsed / 1000;
                long min = totalSec / 60;
                long sec = totalSec % 60;
                long tenths = (elapsed % 1000) / 100;
                binding.tvTimer.setText(String.format(Locale.US, "%02d:%02d.%d", min, sec, tenths));
                timerHandler.postDelayed(this, 100);
            }
        }
    };

    // Recordings library state
    private RecordingsAdapter recordingsAdapter;
    private final List<RecordingItem> allRecordings = new ArrayList<>();
    private String currentlyPlayingId = null;

    private final ActivityResultLauncher<String> requestPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), isGranted -> {
                if (isGranted) {
                    startAudioRecording();
                } else {
                    Toast.makeText(this, R.string.permission_denied, Toast.LENGTH_LONG).show();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        // Initialize audio subsystem
        usbAudioHelper = new UsbAudioHelper(this);
        recorderManager = new AudioRecorderManager(this, usbAudioHelper);
        audioPlayer = new AudioPlayerManager();

        setupHardwarePill();
        setupBottomNavigation();
        setupRecordScreen();
        setupRecordingsLibrary();
    }

    // --- 1. HARDWARE STATUS PILL ---
    private void setupHardwarePill() {
        updateHardwareDisplay(usbAudioHelper.getOptimalInputDeviceInfo());
        usbAudioHelper.startListening(this::updateHardwareDisplay);
        binding.cardHardwarePill.setOnClickListener(v -> showHardwareDetailsDialog());
    }

    private void updateHardwareDisplay(UsbAudioHelper.DeviceInfo info) {
        this.currentDeviceInfo = info;
        if (info.isUsb) {
            binding.cardHardwarePill.setCardBackgroundColor(ContextCompat.getColor(this, R.color.usb_connected_bg));
            binding.cardHardwarePill.setStrokeColor(ContextCompat.getColor(this, R.color.usb_connected_stroke));
            binding.imgHardwareDot.setColorFilter(ContextCompat.getColor(this, R.color.usb_connected_text));
            binding.tvDevicePill.setText("USB DAC (" + (info.sampleRate / 1000) + "k)");
            binding.tvDevicePill.setTextColor(ContextCompat.getColor(this, R.color.usb_connected_text));
        } else {
            binding.cardHardwarePill.setCardBackgroundColor(ContextCompat.getColor(this, R.color.usb_disconnected_bg));
            binding.cardHardwarePill.setStrokeColor(ContextCompat.getColor(this, R.color.usb_disconnected_stroke));
            binding.imgHardwareDot.setColorFilter(ContextCompat.getColor(this, R.color.usb_disconnected_text));
            binding.tvDevicePill.setText("Internal Mic");
            binding.tvDevicePill.setTextColor(ContextCompat.getColor(this, R.color.usb_disconnected_text));
        }
    }

    private void showHardwareDetailsDialog() {
        if (currentDeviceInfo == null) return;

        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle(currentDeviceInfo.isUsb ? "External USB-C DAC/ADC" : "Internal Microphone");
        builder.setMessage(
                "Hardware Interface: " + currentDeviceInfo.name + "\n" +
                "Clock Locked: " + currentDeviceInfo.sampleRate + " Hz\n" +
                "Audio Source: MediaRecorder.AudioSource.UNPROCESSED\n" +
                "AEC / AGC / Noise Suppression: Hardware Bypassed\n\n" +
                currentDeviceInfo.details
        );
        builder.setPositiveButton("Close", (dialog, which) -> dialog.dismiss());
        builder.show();
    }

    // --- 2. BOTTOM NAVIGATION BAR ---
    private void setupBottomNavigation() {
        binding.bottomNavigation.setOnItemSelectedListener(item -> {
            int itemId = item.getItemId();
            if (itemId == R.id.navigation_record) {
                audioPlayer.stop();
                binding.layoutRecordView.setVisibility(View.VISIBLE);
                binding.layoutRecordingsView.setVisibility(View.GONE);
                return true;
            } else if (itemId == R.id.navigation_recordings) {
                binding.layoutRecordView.setVisibility(View.GONE);
                binding.layoutRecordingsView.setVisibility(View.VISIBLE);
                loadRecordingsList();
                return true;
            }
            return false;
        });

        binding.btnEmptyRecordNow.setOnClickListener(v -> {
            binding.bottomNavigation.setSelectedItemId(R.id.navigation_record);
        });
    }

    // --- 3. FIRST SCREEN: CLASSIC MINIMALIST RECORD SCREEN ---
    private void setupRecordScreen() {
        binding.fabRecord.setOnClickListener(v -> {
            if (recorderManager.isRecording()) {
                stopAudioRecording();
            } else {
                checkPermissionAndStartRecording();
            }
        });
    }

    private void checkPermissionAndStartRecording() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startAudioRecording();
        } else {
            requestPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO);
        }
    }

    private void startAudioRecording() {
        audioPlayer.stop();

        File outputDir = getFilesDir();
        String filename = "raw_lung_" + System.currentTimeMillis() + ".wav";
        rawWavFile = new File(outputDir, filename);

        recorderManager.startRecording(rawWavFile, new AudioRecorderManager.RecordingCallback() {
            @Override
            public void onRecordingStarted(int sampleRate, String sourceName) {
                runOnUiThread(() -> {
                    binding.fabRecord.setImageResource(R.drawable.ic_stop);
                    binding.tvRecordActionLabel.setText("RECORDING • TAP TO STOP & SAVE");
                    binding.tvRecordActionLabel.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.record_active));

                    recordingStartTime = System.currentTimeMillis();
                    timerHandler.post(timerRunnable);
                });
            }

            @Override
            public void onAudioLevelUpdate(double dbLevel, int progress) {
                runOnUiThread(() -> {
                    binding.progressAudioLevel.setProgress(progress);
                    if (dbLevel < -70.0) {
                        binding.tvAudioDb.setText("-∞ dBFS");
                    } else {
                        binding.tvAudioDb.setText(String.format(Locale.US, "%.1f dBFS", dbLevel));
                    }
                });
            }

            @Override
            public void onRecordingProgress(long elapsedMillis) {}

            @Override
            public void onRecordingStopped(File savedFile, long durationMillis) {
                runOnUiThread(() -> {
                    onRecordingCompleted(savedFile, durationMillis);
                });
            }

            @Override
            public void onRecordingError(String errorMessage, Exception error) {
                runOnUiThread(() -> {
                    resetRecordingUi();
                    Toast.makeText(MainActivity.this, "Recording error: " + errorMessage, Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private void stopAudioRecording() {
        recorderManager.stopRecording();
    }

    private void onRecordingCompleted(File savedFile, long durationMs) {
        resetRecordingUi();
        this.rawWavFile = savedFile;

        // Show Post-Recording Action Sheet
        showPostRecordingModal(savedFile, durationMs);
    }

    private void resetRecordingUi() {
        timerHandler.removeCallbacks(timerRunnable);
        binding.fabRecord.setImageResource(R.drawable.ic_mic);
        binding.tvRecordActionLabel.setText("TAP TO RECORD");
        binding.tvRecordActionLabel.setTextColor(ContextCompat.getColor(this, R.color.on_surface_muted));
        binding.progressAudioLevel.setProgress(0);
        binding.tvAudioDb.setText("Ready for lung auscultation");
    }

    private void showPostRecordingModal(File savedFile, long durationMs) {
        BottomSheetDialog dialog = new BottomSheetDialog(this);
        View sheetView = getLayoutInflater().inflate(R.layout.dialog_post_recording, null, false);
        dialog.setContentView(sheetView);

        android.widget.TextView tvDetails = sheetView.findViewById(R.id.tvSheetRecordingDetails);
        if (tvDetails != null) {
            String dur = WavUtils.formatDuration((int) durationMs);
            long bytes = savedFile.exists() ? savedFile.length() : 0;
            String size = String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0));
            tvDetails.setText("Saved: " + dur + " • " + size);
        }

        sheetView.findViewById(R.id.btnSheetViewAll).setOnClickListener(v -> {
            dialog.dismiss();
            binding.bottomNavigation.setSelectedItemId(R.id.navigation_recordings);
        });

        sheetView.findViewById(R.id.btnSheetListenCompare).setOnClickListener(v -> {
            dialog.dismiss();
            openSoundDetail(savedFile.getAbsolutePath());
        });

        dialog.show();
    }

    private void openSoundDetail(String filePath) {
        Intent intent = new Intent(this, AnalysisActivity.class);
        intent.putExtra(AnalysisActivity.EXTRA_FILE_PATH, filePath);
        startActivity(intent);
    }

    // --- 4. SECOND SCREEN: RECORDINGS LIBRARY ---
    private void setupRecordingsLibrary() {
        recordingsAdapter = new RecordingsAdapter();
        binding.rvRecordings.setLayoutManager(new LinearLayoutManager(this));
        binding.rvRecordings.setAdapter(recordingsAdapter);

        recordingsAdapter.setOnItemClickListener(item -> {
            audioPlayer.stop();
            recordingsAdapter.setCurrentlyPlayingId(null);
            openSoundDetail(item.getRawFile().getAbsolutePath());
        });

        recordingsAdapter.setOnPlayClickListener(item -> {
            if (item.getId().equals(currentlyPlayingId)) {
                audioPlayer.stop();
                currentlyPlayingId = null;
                recordingsAdapter.setCurrentlyPlayingId(null);
            } else {
                audioPlayer.stop();
                File fileToPlay = item.hasCleaned() ? item.getCleanedFile() : item.getRawFile();
                if (fileToPlay.exists()) {
                    currentlyPlayingId = item.getId();
                    recordingsAdapter.setCurrentlyPlayingId(currentlyPlayingId);
                    audioPlayer.play(fileToPlay);
                }
            }
        });

        audioPlayer.setPlaybackListener(new AudioPlayerManager.PlaybackListener() {
            @Override public void onPlaybackStarted(int durationMs) {}
            @Override public void onPlaybackProgress(int currentPositionMs, int durationMs) {}
            @Override public void onPlaybackPaused() { recordingsAdapter.setCurrentlyPlayingId(null); }
            @Override public void onPlaybackStopped() { recordingsAdapter.setCurrentlyPlayingId(null); }
            @Override public void onPlaybackCompleted() {
                currentlyPlayingId = null;
                recordingsAdapter.setCurrentlyPlayingId(null);
            }
            @Override public void onError(String message) { recordingsAdapter.setCurrentlyPlayingId(null); }
        });

        recordingsAdapter.setOnDeleteClickListener(item -> {
            new AlertDialog.Builder(this)
                    .setTitle("Delete Recording?")
                    .setMessage("Are you sure you want to delete \"" + item.getTitle() + "\"?")
                    .setNegativeButton("Cancel", null)
                    .setPositiveButton("Delete", (dialog, which) -> {
                        if (item.getId().equals(currentlyPlayingId)) {
                            audioPlayer.stop();
                            currentlyPlayingId = null;
                        }
                        if (item.getRawFile().exists()) item.getRawFile().delete();
                        if (item.getCleanedFile() != null && item.getCleanedFile().exists()) {
                            item.getCleanedFile().delete();
                        }
                        loadRecordingsList();
                    })
                    .show();
        });

        binding.etSearchRecordings.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                filterRecordings(s.toString());
            }
            @Override public void afterTextChanged(Editable s) {}
        });
    }

    private void loadRecordingsList() {
        allRecordings.clear();
        File outputDir = getFilesDir();
        File[] files = outputDir.listFiles((dir, name) -> name.startsWith("raw_lung_") && name.endsWith(".wav"));

        if (files != null && files.length > 0) {
            Arrays.sort(files, (a, b) -> Long.compare(b.lastModified(), a.lastModified()));

            int index = 1;
            for (File rawFile : files) {
                String name = rawFile.getName();
                String id = name.replace("raw_lung_", "").replace(".wav", "");
                File cleanedFile = new File(outputDir, "cleaned_10x_lung_" + id + ".wav");

                long durationMs = 0;
                long fileSizeBytes = rawFile.length();
                try {
                    WavUtils.WavHeader header = WavUtils.readWavHeader(rawFile);
                    durationMs = header.durationMs;
                } catch (Exception ignored) {}

                String title = "Lung Auscultation " + (files.length - index + 1);
                index++;

                allRecordings.add(new RecordingItem(
                        id,
                        title,
                        rawFile,
                        cleanedFile.exists() ? cleanedFile : null,
                        rawFile.lastModified(),
                        durationMs,
                        fileSizeBytes
                ));
            }
        }

        filterRecordings(binding.etSearchRecordings.getText() != null ? binding.etSearchRecordings.getText().toString() : "");
    }

    private void filterRecordings(String query) {
        List<RecordingItem> filtered = new ArrayList<>();
        String q = query.trim().toLowerCase();

        for (RecordingItem item : allRecordings) {
            if (q.isEmpty() || item.getTitle().toLowerCase().contains(q) || item.getFormattedDate().toLowerCase().contains(q)) {
                filtered.add(item);
            }
        }

        recordingsAdapter.setItems(filtered);

        binding.tvRecordingsCount.setText(filtered.size() + (filtered.size() == 1 ? " SOUND RECORDED" : " SOUNDS RECORDED"));

        if (filtered.isEmpty()) {
            binding.layoutEmptyState.setVisibility(View.VISIBLE);
            binding.rvRecordings.setVisibility(View.GONE);
        } else {
            binding.layoutEmptyState.setVisibility(View.GONE);
            binding.rvRecordings.setVisibility(View.VISIBLE);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (binding.layoutRecordingsView.getVisibility() == View.VISIBLE) {
            loadRecordingsList();
        }
    }

    @Override
    protected void onDestroy() {
        timerHandler.removeCallbacks(timerRunnable);
        if (usbAudioHelper != null) usbAudioHelper.stopListening();
        if (recorderManager != null && recorderManager.isRecording()) {
            recorderManager.stopRecording();
        }
        if (audioPlayer != null) audioPlayer.release();
        super.onDestroy();
    }
}
