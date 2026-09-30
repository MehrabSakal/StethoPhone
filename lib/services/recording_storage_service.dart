import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../audio/wav_utils.dart';
import '../models/recording_model.dart';

class RecordingStorageService {
  static final RecordingStorageService _instance = RecordingStorageService._internal();
  factory RecordingStorageService() => _instance;
  RecordingStorageService._internal();

  /// Map of recording IDs to custom titles
  final Map<String, String> _customTitles = {};

  /// Retrieves all saved auscultation recordings from app storage.
  Future<List<RecordingModel>> loadRecordings() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return [];

    final List<FileSystemEntity> entities = dir.listSync();
    final List<RecordingModel> recordings = [];
    final Set<String> processedCleanedPaths = {};

    // 1. First pass: find all raw lung files
    final List<File> rawFiles = [];
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.wav')) {
        final fileName = entity.uri.pathSegments.last;
        if (fileName.startsWith('raw_lung_')) {
          rawFiles.add(entity);
        }
      }
    }

    // Sort raw files by modification date (newest first)
    rawFiles.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    int index = 1;
    for (final rawFile in rawFiles) {
      final fileName = rawFile.uri.pathSegments.last;
      final id = fileName.replaceFirst('raw_lung_', '').replaceFirst('.wav', '');

      // Check for corresponding cleaned file
      final cleanedPath = '${dir.path}/cleaned_10x_lung_$id.wav';
      File? cleanedFile;
      final cFile = File(cleanedPath);
      if (cFile.existsSync() && cFile.lengthSync() > WavUtils.wavHeaderSize) {
        cleanedFile = cFile;
        processedCleanedPaths.add(cleanedPath);
      }

      // Read WAV metadata
      Duration duration = Duration.zero;
      int sampleRate = 48000;
      int fileSizeBytes = 0;
      DateTime createdAt = DateTime.now();

      try {
        fileSizeBytes = rawFile.lengthSync();
        createdAt = rawFile.lastModifiedSync();
        if (fileSizeBytes > WavUtils.wavHeaderSize) {
          final header = await WavUtils.readWavHeader(rawFile);
          sampleRate = header.sampleRate;
          duration = Duration(milliseconds: header.durationMs);
        }
      } catch (_) {}

      // If duration is 0, estimate from file size and sample rate
      if (duration.inMilliseconds == 0 && fileSizeBytes > WavUtils.wavHeaderSize) {
        final pcmBytes = fileSizeBytes - WavUtils.wavHeaderSize;
        final ms = (pcmBytes / (sampleRate * 2)) * 1000;
        duration = Duration(milliseconds: ms.toInt());
      }

      final title = _customTitles[id] ?? 'Lung Auscultation ${rawFiles.length - index + 1}';
      index++;

      recordings.add(
        RecordingModel(
          id: id,
          title: title,
          rawFile: rawFile,
          cleanedFile: cleanedFile,
          createdAt: createdAt,
          duration: duration,
          sampleRate: sampleRate,
          fileSizeBytes: fileSizeBytes,
        ),
      );
    }

    // Sort by createdAt descending
    recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return recordings;
  }

  /// Creates a new raw recording file with timestamp.
  Future<File> createNewRawFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return File('${dir.path}/raw_lung_$timestamp.wav');
  }

  /// Returns the expected cleaned file path for a given raw recording.
  File getCleanedFileFor(File rawFile) {
    final fileName = rawFile.uri.pathSegments.last;
    final dir = rawFile.parent.path;
    final id = fileName.replaceFirst('raw_lung_', '').replaceFirst('.wav', '');
    return File('$dir/cleaned_10x_lung_$id.wav');
  }

  /// Deletes a recording and any associated cleaned files.
  Future<void> deleteRecording(RecordingModel recording) async {
    try {
      if (await recording.rawFile.exists()) {
        await recording.rawFile.delete();
      }
    } catch (_) {}

    try {
      if (recording.cleanedFile != null && await recording.cleanedFile!.exists()) {
        await recording.cleanedFile!.delete();
      }
    } catch (_) {}

    _customTitles.remove(recording.id);
  }

  /// Updates recording title
  void renameRecording(RecordingModel recording, String newTitle) {
    _customTitles[recording.id] = newTitle;
    recording.title = newTitle;
  }
}
