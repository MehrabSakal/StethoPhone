package com.respiratory.lungaudio.audio;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Locale;

/**
 * Utility for reading, writing, and updating canonical 44-byte RIFF/WAVE audio files.
 * Ensures bit-perfect raw PCM representation.
 */
public final class WavUtils {

    public static final int WAV_HEADER_SIZE = 44;

    private WavUtils() {}

    /**
     * Data structure holding parsed WAV header parameters.
     */
    public static class WavHeader {
        public final int sampleRate;
        public final int numChannels;
        public final int bitsPerSample;
        public final int audioFormat;
        public final long dataChunkSize;
        public final long durationMs;

        public WavHeader(int sampleRate, int numChannels, int bitsPerSample, int audioFormat, long dataChunkSize) {
            this.sampleRate = sampleRate;
            this.numChannels = numChannels;
            this.bitsPerSample = bitsPerSample;
            this.audioFormat = audioFormat;
            this.dataChunkSize = dataChunkSize;
            int byteRate = sampleRate * numChannels * (bitsPerSample / 8);
            this.durationMs = byteRate > 0 ? (dataChunkSize * 1000L) / byteRate : 0;
        }
    }

    /**
     * Writes a canonical 44-byte RIFF/WAVE header to the provided OutputStream.
     */
    public static void writeWavHeader(OutputStream out, int sampleRate, int channels, int bitsPerSample, long pcmDataSize) throws IOException {
        long totalDataLen = pcmDataSize + 36;
        int byteRate = sampleRate * channels * (bitsPerSample / 8);
        int blockAlign = channels * (bitsPerSample / 8);

        byte[] header = new byte[WAV_HEADER_SIZE];

        // 0-3: 'RIFF'
        header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
        // 4-7: ChunkSize = File size - 8
        header[4] = (byte) (totalDataLen & 0xff);
        header[5] = (byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (byte) ((totalDataLen >> 24) & 0xff);
        // 8-11: 'WAVE'
        header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
        // 12-15: 'fmt '
        header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
        // 16-19: Subchunk1Size (16 for PCM)
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0;
        // 20-21: AudioFormat (1 for Linear PCM)
        header[20] = 1; header[21] = 0;
        // 22-23: NumChannels
        header[22] = (byte) channels; header[23] = 0;
        // 24-27: SampleRate
        header[24] = (byte) (sampleRate & 0xff);
        header[25] = (byte) ((sampleRate >> 8) & 0xff);
        header[26] = (byte) ((sampleRate >> 16) & 0xff);
        header[27] = (byte) ((sampleRate >> 24) & 0xff);
        // 28-31: ByteRate
        header[28] = (byte) (byteRate & 0xff);
        header[29] = (byte) ((byteRate >> 8) & 0xff);
        header[30] = (byte) ((byteRate >> 16) & 0xff);
        header[31] = (byte) ((byteRate >> 24) & 0xff);
        // 32-33: BlockAlign
        header[32] = (byte) blockAlign; header[33] = 0;
        // 34-35: BitsPerSample
        header[34] = (byte) bitsPerSample; header[35] = 0;
        // 36-39: 'data'
        header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
        // 40-43: Subchunk2Size = PCM Data Size
        header[40] = (byte) (pcmDataSize & 0xff);
        header[41] = (byte) ((pcmDataSize >> 8) & 0xff);
        header[42] = (byte) ((pcmDataSize >> 16) & 0xff);
        header[43] = (byte) ((pcmDataSize >> 24) & 0xff);

        out.write(header, 0, WAV_HEADER_SIZE);
    }

    /**
     * Updates the RIFF chunk size and Data subchunk size fields in an existing WAV file
     * using RandomAccessFile seeking.
     */
    public static void updateWavSizes(RandomAccessFile raf, long pcmDataSize) throws IOException {
        long totalDataLen = pcmDataSize + 36;

        // Bytes 4-7: RIFF ChunkSize
        raf.seek(4);
        raf.write((byte) (totalDataLen & 0xff));
        raf.write((byte) ((totalDataLen >> 8) & 0xff));
        raf.write((byte) ((totalDataLen >> 16) & 0xff));
        raf.write((byte) ((totalDataLen >> 24) & 0xff));

        // Bytes 40-43: Data Subchunk2Size
        raf.seek(40);
        raf.write((byte) (pcmDataSize & 0xff));
        raf.write((byte) ((pcmDataSize >> 8) & 0xff));
        raf.write((byte) ((pcmDataSize >> 16) & 0xff));
        raf.write((byte) ((pcmDataSize >> 24) & 0xff));
    }

    /**
     * Parses the canonical 44-byte RIFF/WAVE header of a WAV file.
     */
    public static WavHeader readWavHeader(File file) throws IOException {
        byte[] header = new byte[WAV_HEADER_SIZE];
        try (FileInputStream fis = new FileInputStream(file)) {
            int read = fis.read(header);
            if (read < WAV_HEADER_SIZE) {
                throw new IOException("File too short to be a valid WAV: " + file.getName());
            }
        }

        ByteBuffer buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);

        // Verify "RIFF"
        String riff = new String(header, 0, 4);
        if (!"RIFF".equals(riff)) {
            throw new IOException("Invalid RIFF header: " + riff);
        }

        // Verify "WAVE"
        String wave = new String(header, 8, 4);
        if (!"WAVE".equals(wave)) {
            throw new IOException("Invalid WAVE signature: " + wave);
        }

        int audioFormat = buffer.getShort(20) & 0xffff;
        int numChannels = buffer.getShort(22) & 0xffff;
        int sampleRate = buffer.getInt(24);
        int bitsPerSample = buffer.getShort(34) & 0xffff;
        long dataChunkSize = buffer.getInt(40) & 0xffffffffL;

        return new WavHeader(sampleRate, numChannels, bitsPerSample, audioFormat, dataChunkSize);
    }

    /**
     * Formats milliseconds into standard MM:SS display format.
     */
    public static String formatDuration(long millis) {
        long seconds = millis / 1000;
        long minutes = seconds / 60;
        long remainingSec = seconds % 60;
        return String.format(Locale.US, "%02d:%02d", minutes, remainingSec);
    }

    /**
     * Formats byte size into human readable string (e.g. "1.2 MB").
     */
    public static String formatFileSize(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return String.format(Locale.US, "%.1f KB", bytes / 1024.0);
        return String.format(Locale.US, "%.2f MB", bytes / (1024.0 * 1024.0));
    }
}
