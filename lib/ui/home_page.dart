import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio/native_audio_bridge.dart';
import '../audio/wav_utils.dart';
import '../dsp/advanced_noise_cancellation.dart';
import 'analysis_detail_page.dart';

enum AudioTrackType { raw, cleaned }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final NativeAudioBridge _audioBridge = NativeAudioBridge();
  final AudioPlayer _audioPlayer = AudioPlayer();

  UsbDeviceInfo _deviceInfo = UsbDeviceInfo(
    isUsb: false,
    name: 'Internal Microphone',
    sampleRate: 48000,
    details: 'Unprocessed raw acquisition locked at 48000 Hz.',
  );

  // Recording state
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingMillis = 0;
  double _currentDbLevel = -100.0;
  StreamSubscription<double>? _levelSubscription;

  File? _rawAudioFile;
  File? _cleanedAudioFile;
  WavHeader? _rawHeader;
  WavHeader? _cleanedHeader;

  // DSP & 10x Amplification state
  double _gainMultiplier = 10.0; // 10x linear boost (+20 dB) for ML disease detection
  bool _enableNoiseGate = true;
  bool _isFiltering = false;
  double _filterProgress = 0.0;

  // Playback state (Unified A/B Player)
  AudioTrackType _activeTrack = AudioTrackType.raw;
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _setupAudioPlayer();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadDeviceInfo() async {
    final info = await _audioBridge.getDeviceInfo();
    if (mounted) {
      setState(() => _deviceInfo = info);
    }
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _playbackPosition = pos);
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() => _playbackDuration = dur);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    _levelSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- Recording Logic ---
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showToast('Microphone permission required for auscultation.');
      return;
    }

    await _audioPlayer.stop();

    final dir = await getApplicationDocumentsDirectory();
    final targetPath = '${dir.path}/raw_lung_${DateTime.now().millisecondsSinceEpoch}.wav';
    final targetFile = File(targetPath);

    final bool started = await _audioBridge.startRecording(targetFile.path);
    if (!started) {
      _showToast('Unable to open raw AudioRecord stream.');
      return;
    }

    setState(() {
      _isRecording = true;
      _recordingMillis = 0;
      _rawAudioFile = targetFile;
      _cleanedAudioFile = null;
      _rawHeader = null;
      _cleanedHeader = null;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
    });

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _recordingMillis += 100);
    });

    _levelSubscription = _audioBridge.audioLevelStream.listen((db) {
      if (mounted) setState(() => _currentDbLevel = db);
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    await _levelSubscription?.cancel();

    final recordedPath = await _audioBridge.stopRecording();
    final savedFile = recordedPath != null ? File(recordedPath) : _rawAudioFile!;

    WavHeader? header;
    if (await savedFile.exists() && await savedFile.length() > WavUtils.wavHeaderSize) {
      try {
        header = await WavUtils.readWavHeader(savedFile);
      } catch (_) {}
    }

    setState(() {
      _isRecording = false;
      _currentDbLevel = -100.0;
      _rawAudioFile = savedFile;
      _rawHeader = header;
      _activeTrack = AudioTrackType.raw;
    });

    _showToast('Raw audio saved. Tap "Clean & 10x Amplify" to process.');
  }

  // --- High-Efficiency Noise Reduction & 10x Amplification ---
  Future<void> _applyAdvancedDsp() async {
    if (_rawAudioFile == null || !await _rawAudioFile!.exists()) {
      _showToast('Please record lung sound first.');
      return;
    }

    await _audioPlayer.stop();

    setState(() {
      _isFiltering = true;
      _filterProgress = 0.0;
    });

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/cleaned_10x_lung_${DateTime.now().millisecondsSinceEpoch}.wav';
    final outputFile = File(outPath);

    try {
      final double appliedGain = await AdvancedNoiseCancellation.processWav(
        inputFile: _rawAudioFile!,
        outputFile: outputFile,
        requestedGainMultiplier: _gainMultiplier,
        onProgress: (p) {
          if (mounted) setState(() => _filterProgress = p);
        },
      );

      final header = await WavUtils.readWavHeader(outputFile);

      setState(() {
        _isFiltering = false;
        _cleanedAudioFile = outputFile;
        _cleanedHeader = header;
        _activeTrack = AudioTrackType.cleaned;
      });

      _showToast('5-Pass Pipeline Applied: ${appliedGain.toStringAsFixed(1)}x clean boost!');
    } catch (e) {
      setState(() => _isFiltering = false);
      _showToast('Processing error: $e');
    }
  }

  // --- Playback Logic ---
  File? get _currentAudioFile {
    if (_activeTrack == AudioTrackType.cleaned && _cleanedAudioFile != null) {
      return _cleanedAudioFile;
    }
    return _rawAudioFile;
  }

  Future<void> _togglePlayPause() async {
    final file = _currentAudioFile;
    if (file == null || !await file.exists()) {
      _showToast('No recording available to play.');
      return;
    }

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(file.path));
    }
  }

  Future<void> _switchTrack(AudioTrackType track) async {
    if (_activeTrack == track) return;

    final wasPlaying = _isPlaying;
    final currentPos = _playbackPosition;

    setState(() => _activeTrack = track);

    final newFile = _currentAudioFile;
    if (newFile != null && await newFile.exists()) {
      await _audioPlayer.stop();
      if (wasPlaying) {
        await _audioPlayer.play(DeviceFileSource(newFile.path), position: currentPos);
      }
    }
  }

  void _openDiagnosticAnalysisTab() {
    final file = _currentAudioFile;
    if (file == null || !file.existsSync()) {
      _showToast('Record or clean a sound first to view diagnostics.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => AnalysisDetailPage(
          audioFile: file,
          title: _activeTrack == AudioTrackType.cleaned
              ? 'Cleaned & ${_gainMultiplier.toStringAsFixed(0)}x Amplified Sound'
              : 'Raw Acoustic Sound',
          isCleaned: _activeTrack == AudioTrackType.cleaned,
          gainMultiplier: _gainMultiplier,
        ),
      ),
    );
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

  void _showHardwareDetailsModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _deviceInfo.isUsb ? Icons.usb : Icons.mic,
                      color: _deviceInfo.isUsb ? Colors.green : Theme.of(context).colorScheme.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _deviceInfo.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                _buildInfoRow('Connection', _deviceInfo.isUsb ? 'External USB-C DAC/ADC' : 'Internal Mic (Fallback)'),
                _buildInfoRow('Hardware Sample Rate', '${_deviceInfo.sampleRate} Hz (Clock Matched, Zero Resampling)'),
                _buildInfoRow('Audio Source', 'MediaRecorder.AudioSource.UNPROCESSED'),
                _buildInfoRow('Noise Cancellation', '4th-Order Steep Butterworth (75Hz–1.8kHz) + Noise Gate'),
                _buildInfoRow('Acoustic Amplification', '${_gainMultiplier.toStringAsFixed(0)}x Linear Gain (+20 dB)'),
                _buildInfoRow('Diagnostic Outputs', 'Phonopneumogram (PPG), Spectrogram, Time-Expanded Waveform'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final int totalSec = _recordingMillis ~/ 1000;
    final int min = totalSec ~/ 60;
    final int sec = totalSec % 60;
    final int tenths = (_recordingMillis % 1000) ~/ 100;
    final String timerText =
        '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.$tenths';

    final double levelProgress = ((_currentDbLevel + 60.0) / 60.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.monitor_heart, color: colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PulmoDSP ML',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Auscultation & ML Feature Extractor',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Device status capsule
          InkWell(
            onTap: _showHardwareDetailsModal,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _deviceInfo.isUsb ? const Color(0xFFE8F5E9) : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _deviceInfo.isUsb ? const Color(0xFFA5D6A7) : colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _deviceInfo.isUsb ? Colors.green : Colors.amber.shade700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _deviceInfo.isUsb ? 'USB DAC' : 'Internal Mic',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _deviceInfo.isUsb ? const Color(0xFF2E7D32) : colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // 1. HERO AUSCULTATION RECORDING ZONE
            Center(
              child: Column(
                children: [
                  Text(
                    timerText,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                      color: _isRecording ? Colors.redAccent : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),

                  SizedBox(
                    width: 220,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: levelProgress,
                            minHeight: 6,
                            backgroundColor: colorScheme.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isRecording ? Colors.redAccent : colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRecording
                              ? (_currentDbLevel < -70
                                  ? '-∞ dBFS'
                                  : '${_currentDbLevel.toStringAsFixed(1)} dBFS')
                              : 'Tap to record raw lung acoustics',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: _isRecording ? 'monospace' : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tactile Record Button
                  ScaleTransition(
                    scale: _isRecording ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                    child: GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: _isRecording
                                ? [const Color(0xFFE53935), const Color(0xFFD32F2F)]
                                : [const Color(0xFF00897B), const Color(0xFF00695C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isRecording ? Colors.red : colorScheme.primary).withOpacity(0.35),
                              blurRadius: 18,
                              spreadRadius: 2,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRecording ? 'TAP TO STOP & SAVE' : 'RECORD RAW LUNG AUDIO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: _isRecording ? Colors.redAccent : colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 26),

            // 2. HIGH-EFFICIENCY NOISE CANCELLATION & 10x AMPLIFICATION CARD
            Card(
              elevation: 0,
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: colorScheme.secondary, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Pure Linear Amplification & Band-Pass',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8EAF6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _gainMultiplier <= 0 ? 'Auto-Max' : '${_gainMultiplier.toStringAsFixed(0)}x Boost',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '50 Hz – 2000 Hz Butterworth with zero-distortion linear gain. Preserves 100% of original acoustic timbre without synthetic squashing.',
                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),

                    // Quick Multiplier Chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMultiplierChip(3.0, '3x'),
                        _buildMultiplierChip(6.0, '6x'),
                        _buildMultiplierChip(10.0, '10x'),
                        _buildMultiplierChip(-1.0, 'Auto-Max'),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_isFiltering) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _filterProgress > 0 ? _filterProgress : null,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.tonalIcon(
                        onPressed: (_rawAudioFile != null && !_isFiltering)
                            ? _applyAdvancedDsp
                            : null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: Text(
                          _isFiltering ? 'Denoising & 10x Amplifying…' : 'Clean & 10x Amplify Sound',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 3. COMPARATIVE PLAYER & NEW TAB DIAGNOSTICS LINK
            Card(
              elevation: 0,
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Comparative Auscultation Player',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        if (_currentAudioFile != null)
                          TextButton.icon(
                            onPressed: _openDiagnosticAnalysisTab,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open PPG & Spectrogram Tab', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Modern Segmented A/B Switch
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AudioTrackType>(
                        segments: [
                          ButtonSegment<AudioTrackType>(
                            value: AudioTrackType.raw,
                            icon: const Icon(Icons.raw_on_rounded),
                            label: const Text('Original Raw'),
                            enabled: _rawAudioFile != null,
                          ),
                          ButtonSegment<AudioTrackType>(
                            value: AudioTrackType.cleaned,
                            icon: const Icon(Icons.verified_rounded),
                            label: Text(
                              _cleanedAudioFile != null ? 'Cleaned (${_gainMultiplier.toStringAsFixed(0)}x Boost)' : 'Cleaned (Pending)',
                            ),
                            enabled: _cleanedAudioFile != null,
                          ),
                        ],
                        selected: {_activeTrack},
                        onSelectionChanged: (Set<AudioTrackType> newSelection) {
                          _switchTrack(newSelection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Metadata row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _activeTrack == AudioTrackType.raw
                              ? (_rawHeader != null
                                  ? 'Raw PCM • ${_rawHeader!.sampleRate} Hz'
                                  : 'No raw recording')
                              : (_cleanedHeader != null
                                  ? '4th-Order Bandpass • ${_gainMultiplier.toStringAsFixed(0)}x ML Gain'
                                  : 'Filter not yet applied'),
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          '${WavUtils.formatDuration(_playbackPosition.inMilliseconds)} / ${WavUtils.formatDuration(_playbackDuration.inMilliseconds)}',
                          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Scrubber Slider
                    Slider(
                      value: _playbackPosition.inMilliseconds
                          .toDouble()
                          .clamp(0.0, _playbackDuration.inMilliseconds.toDouble() > 0 ? _playbackDuration.inMilliseconds.toDouble() : 1.0),
                      max: _playbackDuration.inMilliseconds > 0
                          ? _playbackDuration.inMilliseconds.toDouble()
                          : 1.0,
                      onChanged: _currentAudioFile != null
                          ? (val) {
                              _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                            }
                          : null,
                    ),

                    // Playback Action & View Details Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filled(
                          iconSize: 32,
                          padding: const EdgeInsets.all(12),
                          onPressed: _currentAudioFile != null ? _togglePlayPause : null,
                          icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: _currentAudioFile != null ? _openDiagnosticAnalysisTab : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.secondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.analytics_outlined, size: 18),
                          label: const Text('View PPG, Spectrogram & ML Features', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiplierChip(double mult, String label) {
    final isSelected = (_gainMultiplier - mult).abs() < 0.5;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10.5)),
      selected: isSelected,
      onSelected: _isFiltering
          ? null
          : (sel) {
              if (sel) setState(() => _gainMultiplier = mult);
            },
    );
  }
}
