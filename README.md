# PulmoDSP - Respiratory Sound Auscultation, 10x ML Amplification & Diagnostic Analytics

**PulmoDSP** is a clinical-grade respiratory (lung) sound acquisition, real-time signal processing, and machine-learning diagnostic analytics platform built with **Flutter (Dart)** and **Native Android (Java)**.

---

## ⚡ Upgraded Clinical 5-Pass DSP Pipeline

```
Raw WAV File
     │
     ▼
[ PASS 1: Pre-Filtering (Butterworth) ]
 ├── Read 16-bit PCM samples
 ├── Apply 4th-order Bandpass Filter (75 Hz - 2500 Hz)
 └── Removes fundamental heart thump and ultrasonic mic hiss
     │
     ▼
[ PASS 2: Heart & Artifact Separation ]
 ├── Apply Discrete Wavelet Transform (DWT) using db8
 ├── Soft thresholding on high-energy cardiac sub-bands
 └── Reconstruct the signal (Inverse DWT)
     │
     ▼
[ PASS 3: Stationary Noise Reduction ]
 ├── Identify 0.5s of silence (between breaths)
 ├── Calculate noise FFT profile
 └── Apply Spectral Subtraction to remove baseline mic static
     │
     ▼
[ PASS 4: Dynamics & Amplification ]
 ├── Apply Audio Compressor (Ratio 4:1, Fast Attack, Med Release)
 ├── Apply uniform Makeup Gain to raise baseline breathing volume
 └── Hard Limiter at -0.5 dBFS to prevent clipping
     │
     ▼
[ PASS 5: Output Formatting ]
 ├── Convert back to 16-bit signed PCM
 └── Write clean canonical 44-byte WAV
```

### Detailed Pipeline Breakdown
1. **PASS 1: Pre-Filtering (Butterworth 4th-Order Bandpass):**
   - High-Pass: 75 Hz (removes chest wall displacement, body friction, and sub-75Hz heart sound fundamentals).
   - Low-Pass: 2500 Hz (attenuates electronic high-frequency hiss and ambient RF noise).
   - 24 dB/octave attenuation with smooth phase and zero ringing.
2. **PASS 2: Heart & Artifact Separation (DWT db8):**
   - Daubechies 8 (`db8`) wavelet decomposition (16 filter coefficients) chosen because the mother wavelet profile matches phonocardiographic S1/S2 heart sound morphology.
   - Multiresolution soft-thresholding selectively suppresses sharp cardiac beats while leaving continuous stochastic vesicular lung murmurs intact.
3. **PASS 3: Stationary Noise Reduction (Spectral Subtraction):**
   - Automatically scans the audio to isolate a 0.5-second quiescent period (end-expiratory pause).
   - Computes the average noise power spectral density $P_N(f)$.
   - Performs Overlap-Add (OLA) Spectral Subtraction with over-subtraction factor $\alpha \approx 1.75$ and spectral floor $\beta \approx 0.035$ to eliminate baseline microphone static without "musical noise" artifacts.
4. **PASS 4: Dynamics & Amplification:**
   - **Audio Compressor:** 4:1 ratio, 5 ms fast attack, 70 ms medium release with a $-22\text{ dBFS}$ threshold to control loud coughs/clicks and bring forward quiet tidal breathing.
   - **Uniform Makeup Gain:** Boosts the compressed audio by the desired factor ($3\times$, $6\times$, $10\times$, or Auto-Max).
   - **Hard Limiter at -0.5 dBFS:** Clamps any peak exceeding $0.944$ to guarantee zero digital wrap-around clipping and safe DAC output headroom.
5. **PASS 5: Output Formatting:**
   - Serializes back to 16-bit signed PCM little-endian data.
   - Generates a canonical 44-byte RIFF/WAV header with finalized byte lengths.

## 📂 Project Architecture

```
SystemApp/
├── lib/                                            # Flutter / Dart Engine
│   ├── main.dart                                   # Material 3 Minimalist Theme & App Shell
│   ├── models/
│   │   └── recording_model.dart                    # Recording metadata, duration, file management
│   ├── services/
│   │   └── recording_storage_service.dart          # WAV persistence, scanning, creation & deletion
│   ├── dsp/
│   │   ├── advanced_noise_cancellation.dart        # 5-Pass DSP: Butterworth + DWT db8 + 10x Boost
│   │   ├── biquad_filter.dart                      # Direct Form II Transposed Butterworth
│   │   ├── fft_utils.dart                          # Cooley-Tukey Radix-2 FFT & STFT Spectrogram
│   │   ├── ppg_analyzer.dart                       # Phonopneumogram (PPG) Envelope & BPM Detector
│   │   ├── audio_compressor.dart                   # Dynamics compressor & makeup gain
│   │   └── spectral_subtraction.dart               # Noise floor cancellation
│   ├── audio/
│   │   ├── native_audio_bridge.dart                # USB-C AudioRecord PlatformChannel
│   │   └── wav_utils.dart                          # Canonical 44-byte WAV parser & writer
│   └── ui/
│       ├── main_navigation_scaffold.dart           # Bottom navigation (Record ⟷ Recordings)
│       ├── screens/
│       │   ├── record_screen.dart                  # Classic Minimalist Record Screen (Center Record Button)
│       │   ├── recordings_list_screen.dart         # Recordings Library (Search, Inline Preview, Manage)
│       │   └── sound_detail_screen.dart            # Sound Playback, A/B Comparison & Full ML Diagnostics
│       └── widgets/
│           ├── live_waveform_visualizer.dart       # Dynamic live soundwave bars for recording
│           ├── comparison_waveform_widget.dart     # Stacked Raw vs 10x Amplified waveform visualizer
│           ├── spectrogram_widget.dart             # STFT Canvas Heatmap Widget
│           ├── phonopneumogram_widget.dart         # Acoustic PPG Canvas Widget
│           └── time_expanded_waveform.dart         # High-Res Oscillogram Canvas Widget
├── app/                                            # Native Android Module (Java)
│   ├── src/main/java/com/respiratory/lungaudio/
│   │   ├── MainActivity.java                       # Native Android Activity with 10x ML Gain
│   │   ├── FlutterAudioBridge.java                 # PlatformChannel to USB AudioRecord
│   │   └── dsp/
│   │       ├── BiquadFilter.java
│   │       └── LungSoundBandPassFilter.java        # 4th-Order Cascade + 10x Gain in Java
│   └── src/main/res/layout/activity_main.xml       # Native XML layout
```

---

## 🚀 Running the App

### Option A: Flutter (Minimalist UI with Classic Record Screen & Recordings Library)
```bash
flutter pub get
flutter run
```
1. **Record Tab**: Tap the big central record button to capture raw auscultation sound with real-time dB visualizer. Tap again to stop and save.
2. **Recordings Tab**: Browse all recorded sounds via the bottom navigation bar. Preview sounds inline or tap to open.
3. **Sound Detail & Comparison**: Compare actual raw sound vs 10x amplified sound with seamless A/B audio switching, stacked comparison waveforms, STFT Spectrogram, Acoustic PPG, and ML biomarkers.

### Option B: Native Android Studio
1. Open `f:\3-1\SystemApp` in Android Studio.
2. Select your device or emulator and press **Run (▶)**.
3. Record breath sounds, choose **10x ML**, and tap **Clean & Amplify Audio**.
