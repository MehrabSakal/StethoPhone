package com.respiratory.lungaudio.model;

import com.respiratory.lungaudio.audio.WavUtils;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class RecordingItem {
    private final String id;
    private String title;
    private final File rawFile;
    private File cleanedFile;
    private final long timestamp;
    private final long durationMs;
    private final long fileSizeBytes;

    public RecordingItem(String id, String title, File rawFile, File cleanedFile, long timestamp, long durationMs, long fileSizeBytes) {
        this.id = id;
        this.title = title;
        this.rawFile = rawFile;
        this.cleanedFile = cleanedFile;
        this.timestamp = timestamp;
        this.durationMs = durationMs;
        this.fileSizeBytes = fileSizeBytes;
    }

    public String getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public File getRawFile() {
        return rawFile;
    }

    public File getCleanedFile() {
        return cleanedFile;
    }

    public void setCleanedFile(File cleanedFile) {
        this.cleanedFile = cleanedFile;
    }

    public boolean hasCleaned() {
        return cleanedFile != null && cleanedFile.exists() && cleanedFile.length() > WavUtils.WAV_HEADER_SIZE;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public long getDurationMs() {
        return durationMs;
    }

    public String getFormattedDuration() {
        return WavUtils.formatDuration((int) durationMs);
    }

    public String getFormattedDate() {
        SimpleDateFormat sdf = new SimpleDateFormat("MMM d, yyyy • h:mm a", Locale.getDefault());
        return sdf.format(new Date(timestamp));
    }

    public String getFormattedSize() {
        if (fileSizeBytes < 1024) return fileSizeBytes + " B";
        if (fileSizeBytes < 1024 * 1024) {
            return String.format(Locale.US, "%.1f KB", fileSizeBytes / 1024.0);
        }
        return String.format(Locale.US, "%.1f MB", fileSizeBytes / (1024.0 * 1024.0));
    }
}
