import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../audio/native_audio_bridge.dart';
import '../../audio/wav_utils.dart';
import '../../models/recording_model.dart';
import '../../services/recording_storage_service.dart';
import '../widgets/live_waveform_visualizer.dart';
import 'sound_detail_screen.dart';

class RecordScreen extends StatefulWidget {
  final VoidCallback onGoToRecordingsTab;

  const RecordScreen({
    super.key,
    required this.onGoToRecordingsTab,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> with SingleTickerProviderStateMixin {
  final NativeAudioBridge _audioBridge = NativeAudioBridge();
  final RecordingStorageService _storageService = RecordingStorageService();

  UsbDeviceInfo _deviceInfo = UsbDeviceInfo(
    isUsb: false,
    name: 'Internal Microphone',
    sampleRate: 48000,
    details: 'Unprocessed raw acquisition locked at 48000 Hz.',
  );

  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingMillis = 0;
  double _currentDbLevel = -100.0;
  StreamSubscription<double>? _levelSubscription;

  File? _lastRecordedFile;
  RecordingModel? _lastRecording;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadDeviceInfo() async {
    final info = await _audioBridge.getDeviceInfo();
    if (mounted) {
      setState(() => _deviceInfo = info);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    _levelSubscription?.cancel();
    super.dispose();
  }

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

    final targetFile = await _storageService.createNewRawFile();

    final bool started = await _audioBridge.startRecording(targetFile.path);
    if (!started) {
      _showToast('Unable to start recording stream.');
      return;
    }

    _pulseController.repeat(reverse: true);

    setState(() {
      _isRecording = true;
      _recordingMillis = 0;
      _lastRecordedFile = targetFile;
      _lastRecording = null;
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
    _pulseController.stop();
    _pulseController.reset();

    final recordedPath = await _audioBridge.stopRecording();
    final savedFile = recordedPath != null ? File(recordedPath) : _lastRecordedFile!;

    WavHeader? header;
    int durationMs = _recordingMillis;
    int sampleRate = 48000;
    int fileSizeBytes = 0;

    if (await savedFile.exists() && await savedFile.length() > WavUtils.wavHeaderSize) {
      try {
        fileSizeBytes = savedFile.lengthSync();
        header = await WavUtils.readWavHeader(savedFile);
        sampleRate = header.sampleRate;
        if (header.durationMs > 0) durationMs = header.durationMs;
      } catch (_) {}
    }

    final fileName = savedFile.uri.pathSegments.last;
    final id = fileName.replaceFirst('raw_lung_', '').replaceFirst('.wav', '');

    final recording = RecordingModel(
      id: id,
      title: 'Lung Auscultation ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      rawFile: savedFile,
      createdAt: DateTime.now(),
      duration: Duration(milliseconds: durationMs),
      sampleRate: sampleRate,
      fileSizeBytes: fileSizeBytes,
    );

    setState(() {
      _isRecording = false;
      _currentDbLevel = -100.0;
      _lastRecordedFile = savedFile;
      _lastRecording = recording;
    });

    _showPostRecordingSheet(recording);
  }

  void _showPostRecordingSheet(RecordingModel recording) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recording Saved',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${recording.title} • ${recording.formattedDuration} • ${recording.formattedFileSize}',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onGoToRecordingsTab();
                        },
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('View All'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => SoundDetailScreen(recording: recording),
                            ),
                          );
                        },
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Listen & Compare'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
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
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _deviceInfo.name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildInfoRow('Input Source', _deviceInfo.isUsb ? 'External USB-C DAC/ADC' : 'Internal Mic (Auscultation)'),
                _buildInfoRow('Hardware Sample Rate', '${_deviceInfo.sampleRate} Hz (Unprocessed PCM)'),
                _buildInfoRow('Noise Cancellation', 'Butterworth 4th-Order (75Hz-2500Hz)'),
                _buildInfoRow('Cardiac Suppression', 'Daubechies 8 (db8) Wavelet Transform'),
                _buildInfoRow('Amplification', '10x Pure Linear Gain (+20 dBFS)'),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.monitor_heart, color: colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'PulmoDSP',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.3),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _deviceInfo.isUsb ? const Color(0xFFE8F5E9) : colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _deviceInfo.isUsb ? const Color(0xFFA5D6A7) : colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
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
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // 1. MINIMALIST TIMER DISPLAY
            Text(
              timerText,
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w300,
                letterSpacing: 2.0,
                fontFamily: 'monospace',
                color: _isRecording ? const Color(0xFFEF4444) : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            // Live dB Level or Status Subtitle
            Text(
              _isRecording
                  ? (_currentDbLevel < -70 ? '-∞ dBFS' : '${_currentDbLevel.toStringAsFixed(1)} dBFS')
                  : 'Ready for lung auscultation',
              style: TextStyle(
                fontSize: 13,
                fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
                fontFamily: _isRecording ? 'monospace' : null,
                color: _isRecording ? const Color(0xFFEF4444) : colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 24),

            // 2. LIVE WAVEFORM VISUALIZER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: LiveWaveformVisualizer(
                isRecording: _isRecording,
                currentDb: _currentDbLevel,
                activeColor: const Color(0xFFEF4444),
              ),
            ),

            const Spacer(flex: 3),

            // 3. CLASSIC CENTRAL RECORD BUTTON
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _isRecording ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                    child: GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? const Color(0xFFEF4444) : const Color(0xFFEF4444),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withOpacity(_isRecording ? 0.45 : 0.25),
                              blurRadius: _isRecording ? 24 : 14,
                              spreadRadius: _isRecording ? 4 : 1,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: _isRecording ? 32 : 72,
                            height: _isRecording ? 32 : 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(_isRecording ? 8 : 36),
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                              color: const Color(0xFFEF4444),
                              size: _isRecording ? 28 : 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isRecording ? 'RECORDING • TAP TO STOP' : 'TAP TO RECORD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: _isRecording ? const Color(0xFFEF4444) : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}
