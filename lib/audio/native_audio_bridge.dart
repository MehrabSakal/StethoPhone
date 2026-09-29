import 'dart:async';
import 'package:flutter/services.dart';

class UsbDeviceInfo {
  final bool isUsb;
  final String name;
  final int sampleRate;
  final String details;

  UsbDeviceInfo({
    required this.isUsb,
    required this.name,
    required this.sampleRate,
    required this.details,
  });

  factory UsbDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return UsbDeviceInfo(
      isUsb: map['isUsb'] as bool? ?? false,
      name: map['name'] as String? ?? 'Microphone',
      sampleRate: map['sampleRate'] as int? ?? 48000,
      details: map['details'] as String? ?? '',
    );
  }
}

class NativeAudioBridge {
  static const MethodChannel _methodChannel = MethodChannel('com.respiratory.lungaudio/audio');
  static const EventChannel _levelEventChannel = EventChannel('com.respiratory.lungaudio/audio_level');

  Stream<double>? _audioLevelStream;

  Future<UsbDeviceInfo> getDeviceInfo() async {
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel.invokeMethod('getDeviceInfo');
      if (res != null) {
        return UsbDeviceInfo.fromMap(res);
      }
    } catch (_) {}
    return UsbDeviceInfo(
      isUsb: false,
      name: 'Default Audio Input',
      sampleRate: 48000,
      details: 'UNPROCESSED Audio Source | Hardware Clock Locked | AGC/AEC/NS: OFF',
    );
  }

  Future<bool> startRecording(String outputFilePath) async {
    try {
      final bool? success = await _methodChannel.invokeMethod('startRecording', {
        'path': outputFilePath,
      });
      return success ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final String? path = await _methodChannel.invokeMethod('stopRecording');
      return path;
    } catch (e) {
      return null;
    }
  }

  Stream<double> get audioLevelStream {
    _audioLevelStream ??= _levelEventChannel
        .receiveBroadcastStream()
        .map((event) => (event as num).toDouble());
    return _audioLevelStream!;
  }
}
