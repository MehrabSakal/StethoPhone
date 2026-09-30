package com.respiratory.lungaudio;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.SeekBar;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.button.MaterialButtonToggleGroup;
import com.google.android.material.tabs.TabLayout;
import com.respiratory.lungaudio.audio.AudioPlayerManager;
import com.respiratory.lungaudio.audio.WavUtils;
import com.respiratory.lungaudio.databinding.ActivityAnalysisBinding;
import com.respiratory.lungaudio.dsp.FftUtils;
import com.respiratory.lungaudio.dsp.LungSoundBandPassFilter;
import com.respiratory.lungaudio.dsp.PpgAnalyzer;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class AnalysisActivity extends AppCompatActivity {

    public static final String EXTRA_FILE_PATH = "extra_file_path";

    private ActivityAnalysisBinding binding;
    private AudioPlayerManager player;
    private LungSoundBandPassFilter dspFilter;

    private File rawAudioFile;
    private File cleanedAudioFile;
    private boolean isPlayingCleaned = false;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityAnalysisBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        setSupportActionBar(binding.analysisToolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        }
        binding.analysisToolbar.setNavigationOnClickListener(v -> finish());

        String filePath = getIntent().getStringExtra(EXTRA_FILE_PATH);
        if (filePath == null) {
            Toast.makeText(this, "Audio file not specified", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        File targetFile = new File(filePath);
        if (!targetFile.exists()) {
            Toast.makeText(this, "Audio file not found", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        resolveRawAndCleanedFiles(targetFile);

        player = new AudioPlayerManager();
        dspFilter = new LungSoundBandPassFilter();

        setupTabs();
        setupPlayer();
        setupComparisonControls();
        loadAndAnalyzeAudio();
    }

    private void resolveRawAndCleanedFiles(File targetFile) {
        String name = targetFile.getName();
        File parent = targetFile.getParentFile();

        if (name.startsWith("raw_lung_")) {
            rawAudioFile = targetFile;
            String id = name.replace("raw_lung_", "").replace(".wav", "");
            cleanedAudioFile = new File(parent, "cleaned_10x_lung_" + id + ".wav");
            isPlayingCleaned = false;
        } else if (name.startsWith("cleaned_10x_lung_")) {
            cleanedAudioFile = targetFile;
            String id = name.replace("cleaned_10x_lung_", "").replace(".wav", "");
            rawAudioFile = new File(parent, "raw_lung_" + id + ".wav");
            isPlayingCleaned = true;
        } else {
            rawAudioFile = targetFile;
            cleanedAudioFile = new File(parent, "cleaned_10x_" + name);
            isPlayingCleaned = false;
        }
    }

    private File getActiveFile() {
        if (isPlayingCleaned && cleanedAudioFile != null && cleanedAudioFile.exists()) {
            return cleanedAudioFile;
        }
        return rawAudioFile;
    }

    private void setupTabs() {
        binding.analysisTabs.addTab(binding.analysisTabs.newTab().setText("All Diagnostics"));
        binding.analysisTabs.addTab(binding.analysisTabs.newTab().setText("ML Diagnostics"));
        binding.analysisTabs.addTab(binding.analysisTabs.newTab().setText("Spectrogram"));
        binding.analysisTabs.addTab(binding.analysisTabs.newTab().setText("Phonopneumogram (PPG)"));
        binding.analysisTabs.addTab(binding.analysisTabs.newTab().setText("Waveform"));

        binding.analysisTabs.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override
            public void onTabSelected(TabLayout.Tab tab) {
                int pos = tab.getPosition();
                if (pos == 0) {
                    binding.cardMlDiagnostics.setVisibility(View.VISIBLE);
                    binding.cardSpectrogram.setVisibility(View.VISIBLE);
                    binding.cardPpg.setVisibility(View.VISIBLE);
                    binding.cardWaveform.setVisibility(View.VISIBLE);
                } else if (pos == 1) {
                    binding.cardMlDiagnostics.setVisibility(View.VISIBLE);
                    binding.cardSpectrogram.setVisibility(View.GONE);
                    binding.cardPpg.setVisibility(View.GONE);
                    binding.cardWaveform.setVisibility(View.GONE);
                } else if (pos == 2) {
                    binding.cardMlDiagnostics.setVisibility(View.GONE);
                    binding.cardSpectrogram.setVisibility(View.VISIBLE);
                    binding.cardPpg.setVisibility(View.GONE);
                    binding.cardWaveform.setVisibility(View.GONE);
                } else if (pos == 3) {
                    binding.cardMlDiagnostics.setVisibility(View.GONE);
                    binding.cardSpectrogram.setVisibility(View.GONE);
                    binding.cardPpg.setVisibility(View.VISIBLE);
                    binding.cardWaveform.setVisibility(View.GONE);
                } else if (pos == 4) {
                    binding.cardMlDiagnostics.setVisibility(View.GONE);
                    binding.cardSpectrogram.setVisibility(View.GONE);
                    binding.cardPpg.setVisibility(View.GONE);
                    binding.cardWaveform.setVisibility(View.VISIBLE);
                }
            }

            @Override public void onTabUnselected(TabLayout.Tab tab) {}
            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });
    }

    private void setupComparisonControls() {
        boolean hasCleaned = cleanedAudioFile != null && cleanedAudioFile.exists();

        if (hasCleaned) {
            binding.layoutGenerateCallout.setVisibility(View.GONE);
            binding.btnSelectCleaned.setEnabled(true);
            if (isPlayingCleaned) {
                binding.toggleGroupTrack.check(R.id.btnSelectCleaned);
            } else {
                binding.toggleGroupTrack.check(R.id.btnSelectRaw);
            }
        } else {
            binding.layoutGenerateCallout.setVisibility(View.VISIBLE);
            binding.btnSelectCleaned.setEnabled(false);
            binding.toggleGroupTrack.check(R.id.btnSelectRaw);
            isPlayingCleaned = false;
        }

        updateTrackBadge();

        binding.toggleGroupTrack.addOnButtonCheckedListener((group, checkedId, isChecked) -> {
            if (!isChecked) return;

            boolean wasPlaying = player.isPlaying();
            int currentPos = player.getCurrentPosition();

            if (checkedId == R.id.btnSelectRaw) {
                isPlayingCleaned = false;
            } else if (checkedId == R.id.btnSelectCleaned) {
                if (cleanedAudioFile != null && cleanedAudioFile.exists()) {
                    isPlayingCleaned = true;
                } else {
                    Toast.makeText(this, "Amplified file not available yet", Toast.LENGTH_SHORT).show();
                    binding.toggleGroupTrack.check(R.id.btnSelectRaw);
                    return;
                }
            }

            updateTrackBadge();

            // Seamless A/B switching during playback
            if (wasPlaying) {
                player.stop();
                player.play(getActiveFile());
                player.seekTo(currentPos);
            }

            loadAndAnalyzeAudio();
        });

        binding.btnGenerateCleaned.setOnClickListener(v -> generateAmplifiedAudio());
    }

    private void updateTrackBadge() {
        if (isPlayingCleaned) {
            binding.tvTrackInfoBadge.setText("10x Clean Boost • 75-2500 Hz • DWT db8");
            binding.tvMlBadge.setText("10x AMPLIFIED");
            binding.tvMlBadge.setBackgroundResource(R.drawable.bg_badge_clean);
            binding.tvMlBadge.setTextColor(getColor(R.color.badge_clean_text));
            binding.tvGainValue.setText("10.0x (+20dB)");
        } else {
            binding.tvTrackInfoBadge.setText("Raw PCM • 48 kHz • Unprocessed");
            binding.tvMlBadge.setText("RAW ACOUSTIC");
            binding.tvMlBadge.setBackgroundResource(R.drawable.bg_badge_raw);
            binding.tvMlBadge.setTextColor(getColor(R.color.badge_raw_text));
            binding.tvGainValue.setText("1.0x (0dB)");
        }
    }

    private void generateAmplifiedAudio() {
        if (rawAudioFile == null || !rawAudioFile.exists()) {
            Toast.makeText(this, "Raw audio missing", Toast.LENGTH_SHORT).show();
            return;
        }

        binding.progressGenerating.setVisibility(View.VISIBLE);
        binding.btnGenerateCleaned.setEnabled(false);

        dspFilter.processWavAsync(rawAudioFile, cleanedAudioFile, 10.0, new LungSoundBandPassFilter.FilterCallback() {
            @Override
            public void onStart() {}

            @Override
            public void onProgress(int progressPercent) {
                binding.progressGenerating.setProgress(progressPercent);
            }

            @Override
            public void onSuccess(File outputFile, double appliedGainFactor) {
                runOnUiThread(() -> {
                    binding.progressGenerating.setVisibility(View.GONE);
                    binding.layoutGenerateCallout.setVisibility(View.GONE);
                    binding.btnSelectCleaned.setEnabled(true);

                    // Automatically switch to amplified sound!
                    binding.toggleGroupTrack.check(R.id.btnSelectCleaned);
                    Toast.makeText(AnalysisActivity.this, "✨ 10x Amplification Applied!", Toast.LENGTH_SHORT).show();
                });
            }

            @Override
            public void onError(Exception exception) {
                runOnUiThread(() -> {
                    binding.progressGenerating.setVisibility(View.GONE);
                    binding.btnGenerateCleaned.setEnabled(true);
                    Toast.makeText(AnalysisActivity.this, "Amplification error: " + exception.getMessage(), Toast.LENGTH_SHORT).show();
                });
            }
        });
    }

    private void setupPlayer() {
        binding.btnAnalysisPlayPause.setOnClickListener(v -> {
            if (player.isPlaying()) {
                player.pause();
            } else {
                player.play(getActiveFile());
            }
        });

        binding.seekAnalysisPlayer.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                if (fromUser) player.seekTo(progress);
            }

            @Override public void onStartTrackingTouch(SeekBar seekBar) { player.setTrackingUserSeek(true); }
            @Override public void onStopTrackingTouch(SeekBar seekBar) { player.setTrackingUserSeek(false); }
        });

        player.setPlaybackListener(new AudioPlayerManager.PlaybackListener() {
            @Override
            public void onPlaybackStarted(int durationMs) {
                binding.btnAnalysisPlayPause.setIconResource(R.drawable.ic_pause);
                binding.seekAnalysisPlayer.setMax(durationMs);
                binding.tvPlayerTotalTime.setText(WavUtils.formatDuration(durationMs));
            }

            @Override
            public void onPlaybackProgress(int currentPositionMs, int durationMs) {
                binding.seekAnalysisPlayer.setProgress(currentPositionMs);
                binding.tvPlayerCurrentTime.setText(WavUtils.formatDuration(currentPositionMs));
                binding.tvPlayerTotalTime.setText(WavUtils.formatDuration(durationMs));
            }

            @Override
            public void onPlaybackPaused() {
                binding.btnAnalysisPlayPause.setIconResource(R.drawable.ic_play);
            }

            @Override
            public void onPlaybackStopped() {
                binding.btnAnalysisPlayPause.setIconResource(R.drawable.ic_play);
            }

            @Override
            public void onPlaybackCompleted() {
                binding.btnAnalysisPlayPause.setIconResource(R.drawable.ic_play);
                binding.seekAnalysisPlayer.setProgress(0);
                binding.tvPlayerCurrentTime.setText("00:00");
            }

            @Override
            public void onError(String message) {
                binding.btnAnalysisPlayPause.setIconResource(R.drawable.ic_play);
            }
        });
    }

    private void loadAndAnalyzeAudio() {
        File targetFile = getActiveFile();
        if (!targetFile.exists()) return;

        binding.layoutLoading.setVisibility(View.VISIBLE);
        binding.layoutContent.setVisibility(View.GONE);

        executor.execute(() -> {
            try {
                WavUtils.WavHeader header = WavUtils.readWavHeader(targetFile);
                double[] samples = readNormalizedSamples(targetFile, 192000);

                double sampleRate = header.sampleRate;
                double durationSec = header.durationMs / 1000.0;

                // 1. Spectrogram
                double[][] spectrogram = FftUtils.computeSpectrogram(samples, 256, 128, 2500.0, sampleRate);

                // 2. Phonopneumogram
                PpgAnalyzer.PpgResult ppgResult = PpgAnalyzer.analyze(samples, sampleRate, 240);

                // 3. ML features
                MlFeatures ml = extractMlFeatures(samples, sampleRate);

                mainHandler.post(() -> {
                    binding.layoutLoading.setVisibility(View.GONE);
                    binding.layoutContent.setVisibility(View.VISIBLE);

                    // Update Spectrogram
                    binding.spectrogramView.setSpectrogram(spectrogram);
                    binding.tvSpectrogramTimeScale.setText(String.format(Locale.US, "0.0s ────────────────────────────── %.1fs", durationSec));

                    // Update PPG
                    binding.ppgView.setPpgData(ppgResult.envelope, ppgResult.peakIndices);
                    binding.tvPpgTimeScale.setText(String.format(Locale.US, "0.0s ────────────────────────────── %.1fs (%d breaths)", durationSec, ppgResult.peakIndices != null ? ppgResult.peakIndices.size() : 0));

                    // Update Waveform
                    binding.waveformView.setWaveData(samples, isPlayingCleaned);
                    binding.tvWaveformTimeScale.setText(String.format(Locale.US, "0.0s ────────────────────────────── %.1fs", durationSec));

                    // Update ML Metrics
                    binding.tvBpmValue.setText(ppgResult.estimatedBpm + " BPM");
                    binding.tvDominantFreq.setText(String.format(Locale.US, "%.0f Hz", ml.dominantFreqHz));
                    binding.tvSnrValue.setText(String.format(Locale.US, "%.1f dB", ppgResult.snrDb));
                    binding.tvVesicularRatio.setText(String.format(Locale.US, "%.1f%%", ml.vesicularRatio));
                    binding.tvBronchialRatio.setText(String.format(Locale.US, "%.1f%%", ml.bronchialRatio));

                    binding.tvPlayerTotalTime.setText(WavUtils.formatDuration(header.durationMs));
                });
            } catch (Exception e) {
                mainHandler.post(() -> {
                    binding.layoutLoading.setVisibility(View.GONE);
                    binding.layoutContent.setVisibility(View.VISIBLE);
                });
            }
        });
    }

    private static class MlFeatures {
        double dominantFreqHz;
        double vesicularRatio;
        double bronchialRatio;
    }

    private MlFeatures extractMlFeatures(double[] samples, double sampleRate) {
        MlFeatures ml = new MlFeatures();
        if (samples == null || samples.length == 0) return ml;

        int n = Math.min(samples.length, 4096);
        double[] real = new double[4096];
        double[] imag = new double[4096];
        System.arraycopy(samples, 0, real, 0, n);

        FftUtils.fft(real, imag);

        double totalEnergy = 0.0;
        double vesicularEnergy = 0.0;
        double bronchialEnergy = 0.0;
        double maxMag = 0.0;
        int maxBin = 0;
        double freqPerBin = sampleRate / 4096.0;

        for (int k = 1; k < 2048; k++) {
            double freq = k * freqPerBin;
            if (freq > 2500) break;

            double mag = Math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
            totalEnergy += mag;

            if (mag > maxMag) {
                maxMag = mag;
                maxBin = k;
            }

            if (freq >= 100 && freq <= 1000) {
                vesicularEnergy += mag;
            } else if (freq > 1000 && freq <= 2000) {
                bronchialEnergy += mag;
            }
        }

        ml.dominantFreqHz = maxBin * freqPerBin;
        ml.vesicularRatio = totalEnergy > 0 ? (vesicularEnergy / totalEnergy) * 100.0 : 70.0;
        ml.bronchialRatio = totalEnergy > 0 ? (bronchialEnergy / totalEnergy) * 100.0 : 25.0;
        return ml;
    }

    private double[] readNormalizedSamples(File wavFile, int maxSamples) throws IOException {
        try (FileInputStream fis = new FileInputStream(wavFile)) {
            byte[] header = new byte[WavUtils.WAV_HEADER_SIZE];
            int read = fis.read(header);
            if (read < WavUtils.WAV_HEADER_SIZE) return new double[0];

            int availableBytes = fis.available();
            int sampleCount = Math.min(availableBytes / 2, maxSamples);
            double[] samples = new double[sampleCount];

            byte[] buffer = new byte[sampleCount * 2];
            int bytesRead = fis.read(buffer);
            ByteBuffer bb = ByteBuffer.wrap(buffer, 0, bytesRead).order(ByteOrder.LITTLE_ENDIAN);

            for (int i = 0; i < bytesRead / 2; i++) {
                short pcm = bb.getShort();
                samples[i] = pcm / 32768.0;
            }

            return samples;
        }
    }

    @Override
    protected void onDestroy() {
        if (player != null) player.release();
        super.onDestroy();
    }
}
