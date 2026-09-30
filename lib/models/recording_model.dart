import 'dart:io';
import 'package:intl/intl.dart';

/// Represents a single lung auscultation recording with raw and optional cleaned files.
class RecordingModel {
  final String id;
  String title;
  final File rawFile;
  File? cleanedFile;
  final DateTime createdAt;
  final Duration duration;
  final int sampleRate;
  final int fileSizeBytes;
  final double gainMultiplier;

  RecordingModel({
    required this.id,
    required this.title,
    required this.rawFile,
    this.cleanedFile,
    required this.createdAt,
    required this.duration,
    required this.sampleRate,
    required this.fileSizeBytes,
    this.gainMultiplier = 10.0,
  });

  bool get hasCleanedVersion => cleanedFile != null && cleanedFile!.existsSync();

  String get formattedDuration {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.inDays == 0 && now.day == createdAt.day) {
      return 'Today, ${DateFormat('h:mm a').format(createdAt)}';
    } else if (difference.inDays <= 1 && now.day - createdAt.day == 1) {
      return 'Yesterday, ${DateFormat('h:mm a').format(createdAt)}';
    } else {
      return DateFormat('MMM d, yyyy • h:mm a').format(createdAt);
    }
  }

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
