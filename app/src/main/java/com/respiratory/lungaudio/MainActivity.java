package com.respiratory.lungaudio;

import android.Manifest;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.view.View;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.snackbar.Snackbar;
import com.respiratory.lungaudio.audio.AudioPlayerManager;
import com.respiratory.lungaudio.audio.AudioRecorderManager;
import com.respiratory.lungaudio.audio.UsbAudioHelper;
import com.respiratory.lungaudio.audio.WavUtils;
import com.respiratory.lungaudio.databinding.ActivityMainBinding;
import com.respiratory.lungaudio.dsp.LungSoundBandPassFilter;

import java.io.File;
import java.io.IOException;
import java.util.Locale;

/**
 * Standard, clinical-grade Material 3 Activity for acoustic lung sound auscultation.
 * Features a Hero recording zone, preset amplification chips, and a unified A/B comparative player.
 */
public class MainActivity extends AppCompatActivity {

    private enum ActiveTrack { RAW, CLEANED }

    private ActivityMainBinding binding;

    private UsbAudioHelper usbAudioHelper;
    private AudioRecorderManager recorderManager;
    private LungSoundBandPassFilter dspFilter;
    private AudioPlayerManager audioPlayer;

    private UsbAudioHelper.DeviceInfo currentDeviceInfo;
    private File rawWavFile;
    private File cleanedWavFile;
    private WavUtils.WavHeader rawHeader;
    private WavUtils.WavHeader cleanedHeader;

    private ActiveTrack activeTrack = ActiveTrack.RAW;
    private double currentGainMultiplier = 10.0; // 10x linear amplification for audibility and ML

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

        // Initialize audio subsystem & DSP
        usbAudioHelper = new UsbAudioHelper(this);
        recorderManager = new AudioRecorderManager(this, usbAudioHelper);
        dspFilter = new LungSoundBandPassFilter();
        audioPlayer = new AudioPlayerManager();

        setupHardwarePill();
        setupHeroRecording();
        setupDspControls();
        setupUnifiedPlayer();
    }

    // --- 1. HARDWARE STATUS PILL & DETAILS MODAL ---
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
            binding.tvDevicePill.setTextColor(ContextCompat.getColor(this, R.color.on_surface_muted));
        }
    }

    private void showHardwareDetailsDialog() {
        if (currentDeviceInfo == null) return;
        BottomSheetDialog dialog = new BottomSheetDialog(this);
        View view = getLayoutInflater().inflate(R.layout.activity_main, null); // safe fallback container
        dialog.setContentView(createHardwareDetailsView(currentDeviceInfo));
        dialog.show();
    }

    private View createHardwareDetailsView(UsbAudioHelper.DeviceInfo info) {
        android.widget.LinearLayout layout = new android.widget.LinearLayout(this);
        layout.setOrientation(android.widget.LinearLayout.VERTICAL);
        layout.setPadding(48, 48, 48, 48);

        TextView title = new TextView(this);
        title.setText(info.isUsb ? "USB-C Audio Interface" : "Internal Microphone");
        title.setTextSize(18f);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        title.setTextColor(ContextCompat.getColor(this, R.color.on_surface));
        layout.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("Hardware Clock: " + info.sampleRate + " Hz (Zero Resampling)");
        subtitle.setTextSize(13f);
        subtitle.setTextColor(ContextCompat.getColor(this, R.color.primary));
        subtitle.setPadding(0, 8, 0, 24);
        layout.addView(subtitle);

        addInfoRow(layout, "Audio Source", "MediaRecorder.AudioSource.UNPROCESSED");
        addInfoRow(layout, "DSP Pre-processing", "AGC, AEC, NS Bypassed (Raw)");
        addInfoRow(layout, "Filter Architecture", "Cascaded 2nd-Order Butterworth (50Hz–2kHz)");
        addInfoRow(layout, "Acoustic Makeup Gain", "+18 dB with Tanh Soft Saturation");

        return layout;
    }

    private void addInfoRow(android.widget.LinearLayout layout, String label, String val) {
        TextView tv = new TextView(this);
        tv.setText(label + ": " + val);
        tv.setTextSize(12f);
        tv.setTextColor(ContextCompat.getColor(this, R.color.on_surface_muted));
        tv.setPadding(0, 6, 0, 6);
        layout.addView(tv);
    }

    // --- 2. HERO RECORDING CONTROLS ---
    private void setupHeroRecording() {
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
                binding.fabRecord.setImageResource(R.drawable.ic_stop);
                binding.fabRecord.setBackgroundTintList(ColorStateList.valueOf(ContextCompat.getColor(MainActivity.this, R.color.record_active)));
                binding.tvRecordActionLabel.setText("RECORDING RAW AUDIO (TAP TO STOP)");
                binding.tvRecordActionLabel.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.record_active));

                binding.btnRemoveNoise.setEnabled(false);
                binding.btnSelectRaw.setEnabled(false);
                binding.btnSelectCleaned.setEnabled(false);
                binding.btnPlayPause.setEnabled(false);
            }

            @Override
            public void onAudioLevelUpdate(double dbLevel, int progress) {
                binding.progressAudioLevel.setProgress(progress);
                if (dbLevel < -70.0) {
                    binding.tvAudioDb.setText("-∞ dBFS");
                } else {
                    binding.tvAudioDb.setText(String.format(Locale.US, "%.1f dBFS", dbLevel));
                }
            }

            @Override
            public void onRecordingProgress(long elapsedMillis) {
                long totalSec = elapsedMillis / 1000;
                long min = totalSec / 60;
                long sec = totalSec % 60;
                long tenths = (elapsedMillis % 1000) / 100;
                binding.tvRecordingTimer.setText(String.format(Locale.US, "%02d:%02d.%d", min, sec, tenths));
            }

            @Override
            public void onRecordingStopped(File wavFile, long durationMillis) {
                binding.fabRecord.setImageResource(R.drawable.ic_mic);
                binding.fabRecord.setBackgroundTintList(ColorStateList.valueOf(ContextCompat.getColor(MainActivity.this, R.color.primary)));
                binding.tvRecordActionLabel.setText("RECORD RAW LUNG AUDIO");
                binding.tvRecordActionLabel.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.primary));

                binding.progressAudioLevel.setProgress(0);
                binding.tvAudioDb.setText("Recording saved. Ready to filter.");

                try {
                    rawHeader = WavUtils.readWavHeader(wavFile);
                } catch (IOException ignored) {}

                // Enable DSP and Raw Player
                binding.btnRemoveNoise.setEnabled(true);
                binding.btnSelectRaw.setEnabled(true);
                binding.toggleTrackGroup.check(R.id.btnSelectRaw);
                activeTrack = ActiveTrack.RAW;
                updatePlayerTrackDisplay();
            }

            @Override
            public void onRecordingError(String message, Exception e) {
                binding.fabRecord.setImageResource(R.drawable.ic_mic);
                binding.fabRecord.setBackgroundTintList(ColorStateList.valueOf(ContextCompat.getColor(MainActivity.this, R.color.primary)));
                binding.tvRecordActionLabel.setText("RECORD RAW LUNG AUDIO");
                binding.tvAudioDb.setText("Error: " + message);
            }
        });
    }

    private void stopAudioRecording() {
        recorderManager.stopRecording();
    }

    // --- 3. DSP & PRESET GAIN CONTROLS ---
    private void setupDspControls() {
        binding.tvGainValue.setText(String.format(Locale.US, "%.0fx Pure Gain", currentGainMultiplier));

        // Preset Gain Chips (Zero Distortion Pure Linear Scaling)
        binding.chipGain6.setOnClickListener(v -> setGainMultiplier(3.0));
        binding.chipGain12.setOnClickListener(v -> setGainMultiplier(6.0));
        binding.chipGain18.setOnClickListener(v -> setGainMultiplier(10.0));
        binding.chipGain24.setOnClickListener(v -> setGainMultiplier(-1.0)); // Auto-Max

        binding.sliderGain.addOnChangeListener((slider, value, fromUser) -> {
            currentGainMultiplier = value;
            binding.tvGainValue.setText(String.format(Locale.US, "%.0fx Pure Gain", value));
            binding.btnSelectCleaned.setText(String.format(Locale.US, "Cleaned (%.0fx)", value));
        });

        binding.btnRemoveNoise.setOnClickListener(v -> {
            if (rawWavFile == null || !rawWavFile.exists()) {
                Toast.makeText(this, "Please record audio first.", Toast.LENGTH_SHORT).show();
                return;
            }

            audioPlayer.stop();

            String filteredFilename = "cleaned_lung_" + System.currentTimeMillis() + ".wav";
            cleanedWavFile = new File(getFilesDir(), filteredFilename);

            dspFilter.processWavAsync(rawWavFile, cleanedWavFile, currentGainMultiplier, new LungSoundBandPassFilter.FilterCallback() {
                @Override
                public void onStart() {
                    binding.btnRemoveNoise.setEnabled(false);
                    binding.btnRemoveNoise.setText("Clean & Linearly Amplifying…");
                    binding.progressDsp.setVisibility(View.VISIBLE);
                }

                @Override
                public void onProgress(int progressPercent) {
                    binding.progressDsp.setProgress(progressPercent);
                }

                @Override
                public void onSuccess(File outputFile, double appliedGainFactor) {
                    binding.btnRemoveNoise.setEnabled(true);
                    binding.btnRemoveNoise.setText("Clean & Amplify Audio");
                    binding.progressDsp.setVisibility(View.GONE);

                    try {
                        cleanedHeader = WavUtils.readWavHeader(outputFile);
                    } catch (IOException ignored) {}

                    // Enable and switch to cleaned track in player
                    binding.btnSelectCleaned.setEnabled(true);
                    binding.btnSelectCleaned.setText(String.format(Locale.US, "Cleaned (%.1fx)", appliedGainFactor));
                    binding.toggleTrackGroup.check(R.id.btnSelectCleaned);
                    activeTrack = ActiveTrack.CLEANED;
                    updatePlayerTrackDisplay();

                    Snackbar.make(binding.getRoot(), String.format(Locale.US, "5-Pass DSP Applied (%.1fx Boost)!", appliedGainFactor), Snackbar.LENGTH_LONG)
                            .setAction("Play", view -> playCurrentTrack())
                            .show();
                }

                @Override
                public void onError(Exception exception) {
                    binding.btnRemoveNoise.setEnabled(true);
                    binding.btnRemoveNoise.setText("Clean & Amplify Audio");
                    binding.progressDsp.setVisibility(View.GONE);
                    Toast.makeText(MainActivity.this, "DSP Error: " + exception.getMessage(), Toast.LENGTH_LONG).show();
                }
            });
        });
    }

    private void setGainMultiplier(double mult) {
        currentGainMultiplier = mult;
        if (mult <= 0) {
            binding.tvGainValue.setText("Auto-Max (Optimal)");
            binding.btnSelectCleaned.setText("Cleaned (Auto-Max)");
        } else {
            binding.sliderGain.setValue((float) mult);
            binding.tvGainValue.setText(String.format(Locale.US, "%.0fx Pure Gain", mult));
            binding.btnSelectCleaned.setText(String.format(Locale.US, "Cleaned (%.0fx)", mult));
        }
    }

    // --- 4. UNIFIED COMPARATIVE A/B PLAYER ---
    private void setupUnifiedPlayer() {
        binding.toggleTrackGroup.addOnButtonCheckedListener((group, checkedId, isChecked) -> {
            if (!isChecked) return;

            boolean wasPlaying = audioPlayer.isPlaying();
            if (checkedId == R.id.btnSelectRaw) {
                activeTrack = ActiveTrack.RAW;
            } else if (checkedId == R.id.btnSelectCleaned) {
                activeTrack = ActiveTrack.CLEANED;
            }

            updatePlayerTrackDisplay();

            if (wasPlaying) {
                playCurrentTrack();
            }
        });

        binding.btnPlayPause.setOnClickListener(v -> {
            if (audioPlayer.isPlaying()) {
                audioPlayer.pause();
            } else {
                playCurrentTrack();
            }
        });

        binding.btnOpenAnalysis.setOnClickListener(v -> {
            File currentFile = (activeTrack == ActiveTrack.CLEANED) ? cleanedWavFile : rawWavFile;
            if (currentFile != null && currentFile.exists()) {
                android.content.Intent intent = new android.content.Intent(MainActivity.this, AnalysisActivity.class);
                intent.putExtra(AnalysisActivity.EXTRA_FILE_PATH, currentFile.getAbsolutePath());
                intent.putExtra(AnalysisActivity.EXTRA_IS_CLEANED, activeTrack == ActiveTrack.CLEANED);
                intent.putExtra(AnalysisActivity.EXTRA_GAIN_DB, currentGainMultiplier);
                startActivity(intent);
            } else {
                Toast.makeText(MainActivity.this, "Please record or clean audio first.", Toast.LENGTH_SHORT).show();
            }
        });

        binding.seekPlayer.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                if (fromUser) audioPlayer.seekTo(progress);
            }

            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {
                audioPlayer.setTrackingUserSeek(true);
            }

            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {
                audioPlayer.setTrackingUserSeek(false);
            }
        });

        audioPlayer.setPlaybackListener(new AudioPlayerManager.PlaybackListener() {
            @Override
            public void onPlaybackStarted(int durationMs) {
                binding.btnPlayPause.setIconResource(R.drawable.ic_pause);
                binding.seekPlayer.setMax(durationMs);
            }

            @Override
            public void onPlaybackProgress(int currentPositionMs, int durationMs) {
                binding.seekPlayer.setProgress(currentPositionMs);
                binding.tvPlayerDuration.setText(WavUtils.formatDuration(currentPositionMs) + " / " + WavUtils.formatDuration(durationMs));
            }

            @Override
            public void onPlaybackPaused() {
                binding.btnPlayPause.setIconResource(R.drawable.ic_play);
            }

            @Override
            public void onPlaybackStopped() {
                binding.btnPlayPause.setIconResource(R.drawable.ic_play);
            }

            @Override
            public void onPlaybackCompleted() {
                binding.btnPlayPause.setIconResource(R.drawable.ic_play);
                binding.seekPlayer.setProgress(0);
            }

            @Override
            public void onError(String message) {
                binding.btnPlayPause.setIconResource(R.drawable.ic_play);
                Toast.makeText(MainActivity.this, message, Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void updatePlayerTrackDisplay() {
        File currentFile = (activeTrack == ActiveTrack.CLEANED) ? cleanedWavFile : rawWavFile;
        WavUtils.WavHeader currentHeader = (activeTrack == ActiveTrack.CLEANED) ? cleanedHeader : rawHeader;

        if (currentFile != null && currentFile.exists()) {
            binding.btnPlayPause.setEnabled(true);
            binding.seekPlayer.setEnabled(true);
            binding.btnOpenAnalysis.setEnabled(true);
            if (currentHeader != null) {
                String desc = (activeTrack == ActiveTrack.CLEANED)
                        ? String.format(Locale.US, "5-Pass Cleaned (%.1fx • db8 + Spectral Sub)", currentGainMultiplier)
                        : String.format(Locale.US, "Raw 16-bit PCM • %d Hz", currentHeader.sampleRate);
                binding.tvPlayerInfo.setText(desc);
                binding.tvPlayerDuration.setText("00:00 / " + WavUtils.formatDuration(currentHeader.durationMs));
            }
        } else {
            binding.btnPlayPause.setEnabled(false);
            binding.seekPlayer.setEnabled(false);
            binding.btnOpenAnalysis.setEnabled(false);
            binding.tvPlayerInfo.setText("No recording available");
            binding.tvPlayerDuration.setText("00:00 / 00:00");
        }
    }

    private void playCurrentTrack() {
        File currentFile = (activeTrack == ActiveTrack.CLEANED) ? cleanedWavFile : rawWavFile;
        if (currentFile != null && currentFile.exists()) {
            audioPlayer.play(currentFile);
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (recorderManager.isRecording()) {
            recorderManager.stopRecording();
        }
        audioPlayer.pause();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        usbAudioHelper.stopListening();
        audioPlayer.release();
    }
}
