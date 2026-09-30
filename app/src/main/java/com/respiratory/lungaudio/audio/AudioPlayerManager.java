package com.respiratory.lungaudio.audio;

import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.File;
import java.io.IOException;

/**
 * Robust wrapper around Android's MediaPlayer for playing original and filtered WAV files.
 * Handles interactive seekbar progress tracking and state synchronization.
 */
public class AudioPlayerManager {

    private static final String TAG = "AudioPlayerManager";

    public interface PlaybackListener {
        void onPlaybackStarted(int durationMs);
        void onPlaybackProgress(int currentPositionMs, int durationMs);
        void onPlaybackPaused();
        void onPlaybackStopped();
        void onPlaybackCompleted();
        void onError(String message);
    }

    private MediaPlayer mediaPlayer;
    private File currentAudioFile;
    private PlaybackListener listener;
    private final Handler progressHandler = new Handler(Looper.getMainLooper());
    private boolean isTrackingUserSeek = false;

    private final Runnable progressRunnable = new Runnable() {
        @Override
        public void run() {
            if (mediaPlayer != null && mediaPlayer.isPlaying() && !isTrackingUserSeek) {
                try {
                    int pos = mediaPlayer.getCurrentPosition();
                    int dur = mediaPlayer.getDuration();
                    if (listener != null) {
                        listener.onPlaybackProgress(pos, dur);
                    }
                    progressHandler.postDelayed(this, 50);
                } catch (IllegalStateException ignored) {}
            }
        }
    };

    public void setPlaybackListener(PlaybackListener listener) {
        this.listener = listener;
    }

    public boolean isPlaying() {
        try {
            return mediaPlayer != null && mediaPlayer.isPlaying();
        } catch (IllegalStateException e) {
            return false;
        }
    }

    public int getCurrentPosition() {
        if (mediaPlayer != null) {
            try {
                return mediaPlayer.getCurrentPosition();
            } catch (IllegalStateException ignored) {}
        }
        return 0;
    }

    public File getCurrentAudioFile() {
        return currentAudioFile;
    }

    /**
     * Prepares and starts playback of a specified WAV file.
     */
    public void play(File file) {
        if (file == null || !file.exists()) {
            if (listener != null) listener.onError("Audio file does not exist.");
            return;
        }

        // If same file was paused, resume
        if (mediaPlayer != null && file.equals(currentAudioFile)) {
            try {
                mediaPlayer.start();
                startProgressUpdates();
                if (listener != null) {
                    listener.onPlaybackStarted(mediaPlayer.getDuration());
                }
                return;
            } catch (IllegalStateException e) {
                stop();
            }
        }

        // Otherwise reset and load new file
        stop();
        currentAudioFile = file;

        try {
            mediaPlayer = new MediaPlayer();
            mediaPlayer.setAudioAttributes(
                    new AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .build()
            );
            mediaPlayer.setDataSource(file.getAbsolutePath());
            mediaPlayer.setOnPreparedListener(mp -> {
                mp.start();
                startProgressUpdates();
                if (listener != null) {
                    listener.onPlaybackStarted(mp.getDuration());
                }
            });

            mediaPlayer.setOnCompletionListener(mp -> {
                stopProgressUpdates();
                if (listener != null) {
                    listener.onPlaybackCompleted();
                }
            });

            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                stopProgressUpdates();
                if (listener != null) {
                    listener.onError("MediaPlayer error (" + what + ", " + extra + ")");
                }
                return true;
            });

            mediaPlayer.prepareAsync();

        } catch (IOException e) {
            Log.e(TAG, "Error playing audio file", e);
            if (listener != null) {
                listener.onError("Cannot open audio file: " + e.getMessage());
            }
            stop();
        }
    }

    /**
     * Pauses playback.
     */
    public void pause() {
        if (mediaPlayer != null) {
            try {
                if (mediaPlayer.isPlaying()) {
                    mediaPlayer.pause();
                }
            } catch (IllegalStateException ignored) {}
            stopProgressUpdates();
            if (listener != null) {
                listener.onPlaybackPaused();
            }
        }
    }

    /**
     * Stops playback and resets progress.
     */
    public void stop() {
        stopProgressUpdates();
        if (mediaPlayer != null) {
            try {
                if (mediaPlayer.isPlaying()) {
                    mediaPlayer.stop();
                }
            } catch (IllegalStateException ignored) {}
            try {
                mediaPlayer.reset();
                mediaPlayer.release();
            } catch (Exception ignored) {}
            mediaPlayer = null;
        }
        currentAudioFile = null;
        if (listener != null) {
            listener.onPlaybackStopped();
        }
    }

    /**
     * Seeks to position in milliseconds.
     */
    public void seekTo(int positionMs) {
        if (mediaPlayer != null) {
            try {
                mediaPlayer.seekTo(positionMs);
            } catch (IllegalStateException ignored) {}
        }
    }

    public void setTrackingUserSeek(boolean tracking) {
        this.isTrackingUserSeek = tracking;
    }

    private void startProgressUpdates() {
        stopProgressUpdates();
        progressHandler.post(progressRunnable);
    }

    private void stopProgressUpdates() {
        progressHandler.removeCallbacks(progressRunnable);
    }

    /**
     * Clean release on Activity destruction.
     */
    public void release() {
        stop();
    }
}
