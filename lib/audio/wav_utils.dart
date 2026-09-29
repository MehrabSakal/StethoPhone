import 'dart:io';
import 'dart:typed_data';

class WavHeader {
  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;
  final int audioFormat;
  final int dataChunkSize;
  final int durationMs;

  WavHeader({
    required this.sampleRate,
    required this.numChannels,
    required this.bitsPerSample,
    required this.audioFormat,
    required this.dataChunkSize,
  }) : durationMs = (sampleRate * numChannels * (bitsPerSample ~/ 8)) > 0
            ? ((dataChunkSize * 1000) ~/ (sampleRate * numChannels * (bitsPerSample ~/ 8)))
            : 0;
}

class WavUtils {
  static const int wavHeaderSize = 44;

  /// Writes a canonical 44-byte RIFF/WAVE header.
  static Uint8List createWavHeader({
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
    required int pcmDataSize,
  }) {
    final int totalDataLen = pcmDataSize + 36;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);

    final Uint8List header = Uint8List(wavHeaderSize);
    final ByteData bd = ByteData.sublistView(header);

    // 0-3: 'RIFF'
    header.setRange(0, 4, 'RIFF'.codeUnits);
    // 4-7: ChunkSize
    bd.setUint32(4, totalDataLen, Endian.little);
    // 8-11: 'WAVE'
    header.setRange(8, 12, 'WAVE'.codeUnits);
    // 12-15: 'fmt '
    header.setRange(12, 16, 'fmt '.codeUnits);
    // 16-19: Subchunk1Size (16 for PCM)
    bd.setUint32(16, 16, Endian.little);
    // 20-21: AudioFormat (1 for Linear PCM)
    bd.setUint16(20, 1, Endian.little);
    // 22-23: NumChannels
    bd.setUint16(22, numChannels, Endian.little);
    // 24-27: SampleRate
    bd.setUint32(24, sampleRate, Endian.little);
    // 28-31: ByteRate
    bd.setUint32(28, byteRate, Endian.little);
    // 32-33: BlockAlign
    bd.setUint16(32, blockAlign, Endian.little);
    // 34-35: BitsPerSample
    bd.setUint16(34, bitsPerSample, Endian.little);
    // 36-39: 'data'
    header.setRange(36, 40, 'data'.codeUnits);
    // 40-43: Subchunk2Size = PCM Data Size
    bd.setUint32(40, pcmDataSize, Endian.little);

    return header;
  }

  /// Updates chunk size and data size fields in an existing WAV file.
  static Future<void> updateWavSizes(File file, int pcmDataSize) async {
    final RandomAccessFile raf = await file.open(mode: FileMode.append);
    final int totalDataLen = pcmDataSize + 36;

    final Uint8List sizeBuf = Uint8List(4);
    final ByteData bd = ByteData.sublistView(sizeBuf);

    // Update RIFF ChunkSize (bytes 4-7)
    await raf.setPosition(4);
    bd.setUint32(0, totalDataLen, Endian.little);
    await raf.writeFrom(sizeBuf);

    // Update Data Subchunk2Size (bytes 40-43)
    await raf.setPosition(40);
    bd.setUint32(0, pcmDataSize, Endian.little);
    await raf.writeFrom(sizeBuf);

    await raf.close();
  }

  /// Reads and parses the 44-byte WAV header.
  static Future<WavHeader> readWavHeader(File file) async {
    final RandomAccessFile raf = await file.open(mode: FileMode.read);
    final Uint8List header = await raf.read(wavHeaderSize);
    await raf.close();

    if (header.length < wavHeaderSize) {
      throw FormatException('File too small to be a valid WAV');
    }

    final ByteData bd = ByteData.sublistView(header);
    final int audioFormat = bd.getUint16(20, Endian.little);
    final int numChannels = bd.getUint16(22, Endian.little);
    final int sampleRate = bd.getUint32(24, Endian.little);
    final int bitsPerSample = bd.getUint16(34, Endian.little);
    final int dataChunkSize = bd.getUint32(40, Endian.little);

    return WavHeader(
      sampleRate: sampleRate,
      numChannels: numChannels,
      bitsPerSample: bitsPerSample,
      audioFormat: audioFormat,
      dataChunkSize: dataChunkSize,
    );
  }

  static String formatDuration(int millis) {
    final int seconds = millis ~/ 1000;
    final int minutes = seconds ~/ 60;
    final int remainingSec = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSec.toString().padLeft(2, '0')}';
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024.0).toStringAsFixed(1)} KB';
    return '${(bytes / (1024.0 * 1024.0)).toStringAsFixed(2)} MB';
  }
}
