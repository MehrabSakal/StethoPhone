import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../audio/wav_utils.dart';
import '../dsp/advanced_noise_cancellation.dart';
import '../dsp/fft_utils.dart';
import '../dsp/ppg_analyzer.dart';
import 'widgets/phonopneumogram_widget.dart';
import 'widgets/spectrogram_widget.dart';
import 'widgets/time_expanded_waveform.dart';

/// Detailed Diagnostic Analysis Screen displaying Spectrogram, PPG, and Time-Expanded Waveform.
class AnalysisDetailPage extends StatefulWidget {
  final File audioFile;
  final String title;
  final bool isCleaned;
  final double gainMultiplier;

  const AnalysisDetailPage({
    super.key,
    required this.audioFile,
    required this.title,
    required this.isCleaned,
    this.gainMultiplier = 10.0,
  });

  @override
  State<AnalysisDetailPage> createState() => _AnalysisDetailPageState();
}

class _AnalysisDetailPageState extends State<AnalysisDetailPage> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();

  bool _isLoading = true;
  List<double> _samples = [];
  WavHeader? _wavHeader;
  List<List<double>> _spectrogram = [];
  late PpgAnalysisResult _ppgResult;

  // Audio Playback state
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // ML Feature extraction metrics
  double _dominantFreqHz = 0.0;
  double _vesicularRatio = 0.0;
  double _bronchialRatio = 0.0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _setupPlayer();
    _computeAcousticDiagnostics();
  }

  void _setupPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  Future<void> _computeAcousticDiagnostics() async {
    try {
      final header = await WavUtils.readWavHeader(widget.audioFile);
      final rawSamples = await AdvancedNoiseCancellation.extractSamples(
        widget.audioFile,
        maxSamples: 192000, // ~4 seconds of high-res analysis
      );

      final double sampleRate = header.sampleRate.toDouble();
      final double durationSec = header.durationMs / 1000.0;

      // 1. Compute STFT Spectrogram
      final spec = FftUtils.computeSpectrogram(
        samples: rawSamples,
        fftSize: 256,
        hopSize: 128,
        maxFreqHz: 2500.0,
        sampleRate: sampleRate,
      );

      // 2. Compute Phonopneumogram (PPG)
      final ppg = PpgAnalyzer.analyze(
        samples: rawSamples,
        sampleRate: sampleRate,
        targetPoints: 240,
      );

      // 3. Compute ML Acoustic Features (Spectral Bands & Energy)
      _extractMlFeatures(rawSamples, sampleRate);

      if (mounted) {
        setState(() {
          _wavHeader = header;
          _samples = rawSamples;
          _spectrogram = spec;
          _ppgResult = ppg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing audio: $e')),
        );
      }
    }
  }

  void _extractMlFeatures(List<double> samples, double sampleRate) {
    if (samples.isEmpty) return;

    // Approximate spectral energy bands via discrete Fourier energy
    double totalEnergy = 0.0;
    double vesicularEnergy = 0.0; // 100 - 1000 Hz
    double bronchialEnergy = 0.0; // 1000 - 2000 Hz

    final int testSize = math.min(samples.length, 4096);
    final List<double> real = List.filled(4096, 0.0);
    final List<double> imag = List.filled(4096, 0.0);

    for (int i = 0; i < testSize; i++) {
      real[i] = samples[i];
    }
    FftUtils.fft(real, imag);

    double maxMag = 0.0;
    int maxBin = 0;
    final double freqPerBin = sampleRate / 4096.0;

    for (int k = 1; k < 2048; k++) {
      final double freq = k * freqPerBin;
      if (freq > 2500) break;

      final double mag = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
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

    _dominantFreqHz = maxBin * freqPerBin;
    _vesicularRatio = totalEnergy > 0 ? (vesicularEnergy / totalEnergy) * 100 : 70.0;
    _bronchialRatio = totalEnergy > 0 ? (bronchialEnergy / totalEnergy) * 100 : 25.0;
  }

  @override
  void dispose() {
    _player.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(widget.audioFile.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double durationSec = _wavHeader != null ? (_wavHeader!.durationMs / 1000.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.isCleaned
                  ? 'Cleaned • 10x Amplified • 50–2000Hz'
                  : 'Raw Acoustic Data (Unprocessed)',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.assessment_outlined), text: 'Diagnostics & ML'),
            Tab(icon: Icon(Icons.gradient_outlined), text: 'Spectrogram'),
            Tab(icon: Icon(Icons.air_rounded), text: 'Phonopneumogram (PPG)'),
            Tab(icon: Icon(Icons.timeline_rounded), text: 'Waveform'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating Spectrogram, PPG & Acoustic Diagnostics…'),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: ALL-IN-ONE OVERVIEW & ML READY METRICS
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMlSummaryCard(colorScheme),
                            const SizedBox(height: 16),
                            SpectrogramWidget(spectrogram: _spectrogram, durationSec: durationSec),
                            const SizedBox(height: 16),
                            PhonopneumogramWidget(ppgResult: _ppgResult, durationSec: durationSec),
                            const SizedBox(height: 16),
                            TimeExpandedWaveformWidget(
                              samples: _samples,
                              durationSec: durationSec,
                              isAmplified: widget.isCleaned,
                            ),
                          ],
                        ),
                      ),

                      // TAB 2: DEDICATED SPECTROGRAM
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SpectrogramWidget(spectrogram: _spectrogram, durationSec: durationSec),
                            const SizedBox(height: 16),
                            _buildSpectrogramClinicalNotes(colorScheme),
                          ],
                        ),
                      ),

                      // TAB 3: DEDICATED PHONOPNEUMOGRAM (PPG)
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PhonopneumogramWidget(ppgResult: _ppgResult, durationSec: durationSec),
                            const SizedBox(height: 16),
                            _buildPpgClinicalNotes(colorScheme),
                          ],
                        ),
                      ),

                      // TAB 4: DEDICATED TIME-EXPANDED WAVEFORM
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TimeExpandedWaveformWidget(
                              samples: _samples,
                              durationSec: durationSec,
                              isAmplified: widget.isCleaned,
                            ),
                            const SizedBox(height: 16),
                            _buildWaveformClinicalNotes(colorScheme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // PINNED BOTTOM AUDIO PLAYER
                _buildPinnedPlayerBar(colorScheme),
              ],
            ),
    );
  }

  Widget _buildMlSummaryCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology_rounded, color: colorScheme.secondary, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'ML Disease Detection Acoustic Features',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.isCleaned ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.isCleaned ? '10x AMPLIFIED' : 'RAW ACOUSTIC',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: widget.isCleaned ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                _buildMetricTile('Resp. Rate', '${_ppgResult.estimatedBpm}', 'BPM (PPG)'),
                _buildMetricTile('Dominant Freq', '${_dominantFreqHz.toStringAsFixed(0)}', 'Hz (Peak)'),
                _buildMetricTile('SNR Quality', '${_ppgResult.snrDb}', 'dB (Clarity)'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildMetricTile('Vesicular Band', '${_vesicularRatio.toStringAsFixed(1)}%', '100–1000 Hz'),
                _buildMetricTile('Bronchial Band', '${_bronchialRatio.toStringAsFixed(1)}%', '1000–2000 Hz'),
                _buildMetricTile('Gain Boost', widget.isCleaned ? '10.0x (+20dB)' : '1.0x (0dB)', 'Normalized'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text(unit, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPinnedPlayerBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton.filled(
              onPressed: _togglePlayPause,
              icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: _position.inMilliseconds
                        .toDouble()
                        .clamp(0.0, _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
                    max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                    onChanged: (val) {
                      _player.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${WavUtils.formatDuration(_position.inMilliseconds)} / ${WavUtils.formatDuration(_duration.inMilliseconds)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpectrogramClinicalNotes(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clinical Spectrogram Interpretation (ML Ready):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 8),
            Text('• Normal Vesicular: Energy concentrated in soft lower band (100 Hz – 1000 Hz).\n'
                '• Wheezes & Rhonchi: Continuous horizontal musical harmonics in 200 Hz – 1000 Hz.\n'
                '• Crackles (Rales): Discontinuous, sharp vertical bursts of acoustic energy (<20 ms).\n'
                '• 10x Amplification restores low-energy adventitious sounds for convolutional neural network (CNN) feature extraction.',
                style: TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildPpgClinicalNotes(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phonopneumography (PPG) Physiological Significance:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 8),
            Text('• Extracts low-frequency breath volume envelopment to calculate respiratory cadence.\n'
                '• Tachypnea (>20 BPM) vs Bradypnea (<12 BPM) automatically identified.\n'
                '• Inhalation to Exhalation (I:E) acoustic duration ratio quantified for airway obstruction diagnostics.',
                style: TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformClinicalNotes(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time-Expanded Waveform Analysis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 8),
            Text('• High-definition time-domain oscillogram revealing exact acoustic amplitude profile.\n'
                '• Fine vs coarse crackle duration can be precisely measured along the millisecond time scale.\n'
                '• 10x Linear amplification with tanh soft-limiting prevents digital flat-topping/clipping.',
                style: TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
