import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A sleek, minimalistic real-time waveform visualizer for recording sessions.
class LiveWaveformVisualizer extends StatefulWidget {
  final bool isRecording;
  final double currentDb;
  final Color activeColor;

  const LiveWaveformVisualizer({
    super.key,
    required this.isRecording,
    required this.currentDb,
    this.activeColor = const Color(0xFFEF4444),
  });

  @override
  State<LiveWaveformVisualizer> createState() => _LiveWaveformVisualizerState();
}

class _LiveWaveformVisualizerState extends State<LiveWaveformVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<double> _barHeights = List.generate(32, (index) => 0.1);
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_updateBars);

    if (widget.isRecording) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(LiveWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _animController.repeat();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _animController.stop();
      setState(() {
        for (int i = 0; i < _barHeights.length; i++) {
          _barHeights[i] = 0.08;
        }
      });
    }
  }

  void _updateBars() {
    if (!widget.isRecording) return;

    // Normalize dBFS (-60 to 0) to 0.0 - 1.0
    final double normLevel = ((widget.currentDb + 60.0) / 60.0).clamp(0.05, 1.0);

    setState(() {
      // Shift bars left
      for (int i = 0; i < _barHeights.length - 1; i++) {
        _barHeights[i] = _barHeights[i + 1];
      }
      // Add new randomized bar proportional to dB level
      final variation = (_random.nextDouble() * 0.4) - 0.2;
      _barHeights[_barHeights.length - 1] = (normLevel + variation).clamp(0.08, 1.0);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barHeights.length, (index) {
          final heightFactor = _barHeights[index];
          final double barHeight = (heightFactor * 54.0).clamp(4.0, 54.0);

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            width: 3.5,
            height: barHeight,
            decoration: BoxDecoration(
              color: widget.isRecording
                  ? widget.activeColor.withOpacity(0.4 + (heightFactor * 0.6))
                  : colorScheme.outlineVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2.0),
            ),
          );
        }),
      ),
    );
  }
}
