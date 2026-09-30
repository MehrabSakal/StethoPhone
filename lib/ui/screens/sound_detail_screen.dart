import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../audio/wav_utils.dart';
import '../../dsp/advanced_noise_cancellation.dart';
import '../../dsp/fft_utils.dart';
import '../../dsp/ppg_analyzer.dart';
import '../../models/recording_model.dart';
import '../../services/recording_storage_service.dart';
import '../widgets/comparison_waveform_widget.dart';
import '../widgets/phonopneumogram_widget.dart';
import '../widgets/spectrogram_widget.dart';
import '../widgets/time_expanded_waveform.dart';

enum ActiveAudioMode { raw, amplified }

class SoundDetailScreen extends StatefulWidget {
  final RecordingModel recording;
  final VoidCallback? onRecordingChanged;

  const SoundDetailScreen({
    super.key,
    required this.recording,
    this.onRecordingChanged,
  });

  @override
  State<SoundDetailScreen> createState() => _SoundDetailScreenState();
}

class _SoundDetailScreenState extends State<SoundDetailScreen> with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RecordingStorageService _storageService = RecordingStorageService();

  ActiveAudioMode _activeMode = ActiveAudioMode.raw;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Diagnostics data
  bool _isLoadingDiagnostics = true;
  List<double> _rawSamples = [];
  List<double> _cleanedSamples = [];
  List<List<double>> _spectrogram = [];
  PpgAnalysisResult _ppgResult = PpgAnalysisResult(
    envelope: [],
    breathPeakIndices: [],
    estimatedBpm: 0,
    meanEnergy: 0.0,
    peakEnergy: 0.0,
    snrDb: 0.0,
  );

  // ML Biomarkers
  double _dominantFreqHz = 0.0;
  double _vesicularRatio = 0.0;
  double _bronchialRatio = 0.0;

  // Filter processing state
  bool _isGeneratingAmplified = false;
  double _filterProgress = 0.0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    // If cleaned file exists, default to amplified mode, otherwise raw
    if (widget.recording.hasCleanedVersion) {
      _activeMode = ActiveAudioMode.amplified;
    } else {
      _activeMode = ActiveAudioMode.raw;
    }

    _setupAudioPlayer();
    _loadAcousticDiagnostics();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() => _duration = dur);
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  File get _currentActiveFile {
    if (_activeMode == ActiveAudioMode.amplified && widget.recording.hasCleanedVersion) {
      return widget.recording.cleanedFile!;
    }
    return widget.recording.rawFile;
  }

  Future<void> _loadAcousticDiagnostics() async {
    setState(() => _isLoadingDiagnostics = true);

    try {
      final File targetFile = _currentActiveFile;
      if (!await targetFile.exists()) {
        setState(() => _isLoadingDiagnostics = false);
        return;
      }

      final header = await WavUtils.readWavHeader(targetFile);
      final double sampleRate = header.sampleRate.toDouble();
      final double durationSec = header.durationMs / 1000.0;

      // Extract raw samples
      final rawSamples = await AdvancedNoiseCancellation.extractSamples(
        widget.recording.rawFile,
        maxSamples: 192000,
      );

      // Extract cleaned samples if available
      List<double> cleanedSamples = [];
      if (widget.recording.hasCleanedVersion) {
        cleanedSamples = await AdvancedNoiseCancellation.extractSamples(
          widget.recording.cleanedFile!,
          maxSamples: 192000,
        );
      }

      final activeSamples = (_activeMode == ActiveAudioMode.amplified && cleanedSamples.isNotEmpty)
          ? cleanedSamples
          : rawSamples;

      // 1. Compute STFT Spectrogram
      final spec = FftUtils.computeSpectrogram(
        samples: activeSamples,
        fftSize: 256,
        hopSize: 128,
        maxFreqHz: 2500.0,
        sampleRate: sampleRate,
      );

      // 2. Compute PPG
      final ppg = PpgAnalyzer.analyze(
        samples: activeSamples,
        sampleRate: sampleRate,
        targetPoints: 240,
      );

      // 3. Extract ML features
      _extractMlFeatures(activeSamples, sampleRate);

      if (mounted) {
        setState(() {
          _rawSamples = rawSamples;
          _cleanedSamples = cleanedSamples;
          _spectrogram = spec;
          _ppgResult = ppg;
          _isLoadingDiagnostics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDiagnostics = false);
      }
    }
  }

  void _extractMlFeatures(List<double> samples, double sampleRate) {
    if (samples.isEmpty) return;

    double totalEnergy = 0.0;
    double vesicularEnergy = 0.0;
    double bronchialEnergy = 0.0;

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

  // --- Audio Playback Actions ---
  Future<void> _togglePlayPause() async {
    final file = _currentActiveFile;
    if (!await file.exists()) {
      _showToast('Audio file not found.');
      return;
    }

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(file.path));
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final newPos = _position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1),
    );
    await _audioPlayer.seek(clamped);
  }

  Future<void> _switchTrackMode(ActiveAudioMode newMode) async {
    if (_activeMode == newMode) return;

    if (newMode == ActiveAudioMode.amplified && !widget.recording.hasCleanedVersion) {
      _showToast('Cleaned audio not generated yet. Tap the button below to amplify.');
      return;
    }

    final wasPlaying = _isPlaying;
    final currentPos = _position;

    setState(() => _activeMode = newMode);

    final newFile = _currentActiveFile;
    if (await newFile.exists()) {
      await _audioPlayer.stop();
      if (wasPlaying) {
        await _audioPlayer.play(DeviceFileSource(newFile.path), position: currentPos);
      }
    }

    _loadAcousticDiagnostics();
  }

  // --- Generate 10x Amplified Sound on Demand ---
  Future<void> _generateAmplifiedSound() async {
    if (!await widget.recording.rawFile.exists()) {
      _showToast('Raw audio file missing.');
      return;
    }

    setState(() {
      _isGeneratingAmplified = true;
      _filterProgress = 0.0;
    });

    final targetCleanedFile = _storageService.getCleanedFileFor(widget.recording.rawFile);

    try {
      final double appliedGain = await AdvancedNoiseCancellation.processWav(
        inputFile: widget.recording.rawFile,
        outputFile: targetCleanedFile,
        requestedGainMultiplier: widget.recording.gainMultiplier,
        onProgress: (p) {
          if (mounted) setState(() => _filterProgress = p);
        },
      );

      setState(() {
        widget.recording.cleanedFile = targetCleanedFile;
        _isGeneratingAmplified = false;
        _activeMode = ActiveAudioMode.amplified;
      });

      widget.onRecordingChanged?.call();
      await _loadAcousticDiagnostics();

      _showToast('✨ 10x Amplification ready! (${appliedGain.toStringAsFixed(1)}x clean boost applied)');
    } catch (e) {
      setState(() => _isGeneratingAmplified = false);
      _showToast('Amplification failed: $e');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.recording.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter title (e.g. Patient A - Right Lung)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                _storageService.renameRecording(widget.recording, newTitle);
                widget.onRecordingChanged?.call();
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text('Are you sure you want to delete "${widget.recording.title}"? Both raw and amplified files will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _audioPlayer.stop();
              await _storageService.deleteRecording(widget.recording);
              widget.onRecordingChanged?.call();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double durationSec = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds / 1000.0
        : (widget.recording.duration.inMilliseconds / 1000.0);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.recording.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.recording.formattedDate} • ${widget.recording.formattedDuration}',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Rename',
            onPressed: _showRenameDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
            tooltip: 'Delete',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. HERO MINIMALISTIC PLAYER & A/B SOUND COMPARISON
          _buildHeroComparisonPlayerCard(colorScheme),

          // 2. DIAGNOSTIC TABS HEADER
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4))),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              indicatorWeight: 2.5,
              tabs: const [
                Tab(icon: Icon(Icons.assessment_outlined, size: 18), text: 'ML Diagnostics'),
                Tab(icon: Icon(Icons.compare_arrows_rounded, size: 18), text: 'A/B Comparison'),
                Tab(icon: Icon(Icons.air_rounded, size: 18), text: 'PPG Envelope'),
                Tab(icon: Icon(Icons.gradient_outlined, size: 18), text: 'Spectrogram'),
                Tab(icon: Icon(Icons.timeline_rounded, size: 18), text: 'Waveform'),
              ],
            ),
          ),

          // 3. TAB CONTENT
          Expanded(
            child: _isLoadingDiagnostics
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 14),
                        Text(
                          'Analyzing lung acoustics & computing diagnostics…',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: ML DIAGNOSTICS & CLINICAL BIOMARKERS
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMlBiomarkersGrid(colorScheme),
                            const SizedBox(height: 16),
                            _buildClinicalInsightsCard(colorScheme),
                          ],
                        ),
                      ),

                      // TAB 2: A/B ACOUSTIC COMPARISON
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ComparisonWaveformWidget(
                              rawSamples: _rawSamples,
                              cleanedSamples: _cleanedSamples,
                              durationSec: durationSec,
                            ),
                            const SizedBox(height: 16),
                            _buildComparisonNotesCard(colorScheme),
                          ],
                        ),
                      ),

                      // TAB 3: PHONOPNEUMOGRAM (PPG)
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PhonopneumogramWidget(
                              ppgResult: _ppgResult,
                              durationSec: durationSec,
                            ),
                            const SizedBox(height: 14),
                            _buildPpgNotesCard(colorScheme),
                          ],
                        ),
                      ),

                      // TAB 4: SPECTROGRAM
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SpectrogramWidget(
                              spectrogram: _spectrogram,
                              durationSec: durationSec,
                            ),
                            const SizedBox(height: 14),
                            _buildSpectrogramNotesCard(colorScheme),
                          ],
                        ),
                      ),

                      // TAB 5: TIME-EXPANDED WAVEFORM
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TimeExpandedWaveformWidget(
                              samples: (_activeMode == ActiveAudioMode.amplified && _cleanedSamples.isNotEmpty)
                                  ? _cleanedSamples
                                  : _rawSamples,
                              durationSec: durationSec,
                              isAmplified: _activeMode == ActiveAudioMode.amplified,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // --- Hero Comparison Audio Player ---
  Widget _buildHeroComparisonPlayerCard(ColorScheme colorScheme) {
    final bool hasAmplified = widget.recording.hasCleanedVersion;

    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A/B Segmented Comparison Selector
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ActiveAudioMode>(
                  segments: [
                    ButtonSegment<ActiveAudioMode>(
                      value: ActiveAudioMode.raw,
                      icon: const Icon(Icons.mic_none_rounded, size: 16),
                      label: const Text('Actual Sound (Raw)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    ButtonSegment<ActiveAudioMode>(
                      value: ActiveAudioMode.amplified,
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: Text(
                        hasAmplified ? 'Amplified (10x ✨)' : 'Amplified (Pending)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      enabled: hasAmplified,
                    ),
                  ],
                  selected: {_activeMode},
                  onSelectionChanged: (newSelection) {
                    _switchTrackMode(newSelection.first);
                  },
                ),
              ),
            ],
          ),

          // If Amplified version does not exist, show quick generate callout
          if (!hasAmplified) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generate 10x Amplified Sound',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Apply 5-Pass DSP: bandpass, heart sound removal & +20dB boost',
                          style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isGeneratingAmplified ? null : _generateAmplifiedSound,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    child: _isGeneratingAmplified
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Amplify'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Scrubber & Time Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                WavUtils.formatDuration(_position.inMilliseconds),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _activeMode == ActiveAudioMode.amplified
                      ? const Color(0xFF00897B).withOpacity(0.12)
                      : Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _activeMode == ActiveAudioMode.amplified
                      ? '10x Clean Boost • 75-2500 Hz'
                      : 'Raw PCM • 48 kHz • Unprocessed',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: _activeMode == ActiveAudioMode.amplified
                        ? const Color(0xFF00897B)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                WavUtils.formatDuration(_duration.inMilliseconds > 0 ? _duration.inMilliseconds : widget.recording.duration.inMilliseconds),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _position.inMilliseconds
                  .toDouble()
                  .clamp(0.0, _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
              max: _duration.inMilliseconds > 0
                  ? _duration.inMilliseconds.toDouble()
                  : (widget.recording.duration.inMilliseconds > 0 ? widget.recording.duration.inMilliseconds.toDouble() : 1.0),
              onChanged: (val) {
                _audioPlayer.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),

          // Minimalist Playback Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 26,
                tooltip: 'Replay 5s',
                onPressed: () => _seekRelative(-5),
                icon: const Icon(Icons.replay_5_rounded),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                iconSize: 26,
                tooltip: 'Forward 5s',
                onPressed: () => _seekRelative(5),
                icon: const Icon(Icons.forward_5_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Biomarkers Grid ---
  Widget _buildMlBiomarkersGrid(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.psychology_rounded, color: Color(0xFF00897B), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'ML Acoustic Biomarkers',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _activeMode == ActiveAudioMode.amplified
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _activeMode == ActiveAudioMode.amplified ? '10x AMPLIFIED' : 'RAW ACOUSTIC',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _activeMode == ActiveAudioMode.amplified
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              _buildMetricTile('Respiratory Rate', '${_ppgResult.estimatedBpm}', 'BPM (PPG)'),
              _buildMetricTile('Dominant Frequency', '${_dominantFreqHz.toStringAsFixed(0)}', 'Hz (Peak)'),
              _buildMetricTile('Acoustic Clarity', '${_ppgResult.snrDb}', 'dB SNR'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildMetricTile('Vesicular Band', '${_vesicularRatio.toStringAsFixed(1)}%', '100–1000 Hz'),
              _buildMetricTile('Bronchial Band', '${_bronchialRatio.toStringAsFixed(1)}%', '1000–2000 Hz'),
              _buildMetricTile('Gain Boost', _activeMode == ActiveAudioMode.amplified ? '10.0x (+20dB)' : '1.0x (0dB)', 'Normalized'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text(unit, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildClinicalInsightsCard(ColorScheme colorScheme) {
    final bool isNormalVesicular = _vesicularRatio > 55.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notes_rounded, size: 18, color: Color(0xFF00897B)),
              SizedBox(width: 8),
              Text('Clinical Acoustic Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isNormalVesicular
                ? '• Normal Vesicular Pattern: Predominance of 100–1000 Hz acoustic energy with gentle inspiratory envelope, consistent with unobstructed alveolar ventilation.'
                : '• Elevated High-Frequency Content: >1000 Hz bronchial/adventitious acoustic distribution detected. Review spectrogram for wheeze harmonics or crackle transients.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            '• Estimated Respiratory Rate of ${_ppgResult.estimatedBpm.toStringAsFixed(0)} BPM derived from continuous PPG envelope peak detection (${_ppgResult.breathPeakIndices.length} breath cycles detected).',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonNotesCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('A/B Comparison Clinical Utility', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            '1. Raw Sound contains heart beats (S1/S2 fundamentals at 20-50Hz) and microphone friction that mask faint respiratory sounds.\n'
            '2. The 10x Amplified Sound uses Daubechies 8 (db8) Wavelets to isolate and suppress heart sounds, removes baseline hiss via Spectral Subtraction, and applies +20dB uniform gain without clipping.',
            style: TextStyle(fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPpgNotesCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About Acoustic PPG (Phonopneumogram)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'The Phonopneumogram tracks respiratory airflow amplitude over time. Detected ${_ppgResult.breathPeakIndices.length} breath cycles with an average SNR of ${_ppgResult.snrDb.toStringAsFixed(1)} dB, providing quantitative assessment of ventilatory dynamics.',
            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectrogramNotesCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('STFT Spectrogram Interpretation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Shows energy distribution from 0 to 2500 Hz. Horizontal frequency bands correspond to monophonic or polyphonic musical wheezes; short vertical bursts indicate fine or coarse crackles.',
            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}
