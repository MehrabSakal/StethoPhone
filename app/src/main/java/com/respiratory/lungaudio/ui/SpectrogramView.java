package com.respiratory.lungaudio.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.AttributeSet;
import android.view.View;

import androidx.annotation.Nullable;

/**
 * Custom Android View for rendering the STFT Spectrogram Heatmap.
 */
public class SpectrogramView extends View {

    private double[][] spectrogram;
    private final Paint cellPaint = new Paint();

    public SpectrogramView(Context context) {
        super(context);
        init();
    }

    public SpectrogramView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        cellPaint.setStyle(Paint.Style.FILL);
    }

    public void setSpectrogram(double[][] spectrogram) {
        this.spectrogram = spectrogram;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (spectrogram == null || spectrogram.length == 0) return;

        int numFrames = spectrogram.length;
        int numBins = spectrogram[0].length;
        float w = getWidth();
        float h = getHeight();

        float colWidth = w / numFrames;
        float rowHeight = h / numBins;

        for (int t = 0; t < numFrames; t++) {
            float x = t * colWidth;
            double[] spectrum = spectrogram[t];

            for (int f = 0; f < numBins; f++) {
                // High frequencies at top, low frequencies at bottom
                float y = h - ((f + 1) * rowHeight);
                double intensity = spectrum[f];

                cellPaint.setColor(getHeatmapColor(intensity));
                canvas.drawRect(x, y, x + colWidth + 0.5f, y + rowHeight + 0.5f, cellPaint);
            }
        }
    }

    private int getHeatmapColor(double val) {
        float v = (float) Math.max(0.0, Math.min(1.0, val));
        if (v < 0.25f) {
            float t = v / 0.25f;
            return interpolateColor(0xFF0B1120, 0xFF004D40, t);
        } else if (v < 0.55f) {
            float t = (v - 0.25f) / 0.30f;
            return interpolateColor(0xFF004D40, 0xFF00897B, t);
        } else if (v < 0.80f) {
            float t = (v - 0.55f) / 0.25f;
            return interpolateColor(0xFF00897B, 0xFFFFB300, t);
        } else {
            float t = (v - 0.80f) / 0.20f;
            return interpolateColor(0xFFFFB300, 0xFFE53935, t);
        }
    }

    private int interpolateColor(int c1, int c2, float t) {
        int a = (int) (Color.alpha(c1) + t * (Color.alpha(c2) - Color.alpha(c1)));
        int r = (int) (Color.red(c1) + t * (Color.red(c2) - Color.red(c1)));
        int g = (int) (Color.green(c1) + t * (Color.green(c2) - Color.green(c1)));
        int b = (int) (Color.blue(c1) + t * (Color.blue(c2) - Color.blue(c1)));
        return Color.argb(a, r, g, b);
    }
}
