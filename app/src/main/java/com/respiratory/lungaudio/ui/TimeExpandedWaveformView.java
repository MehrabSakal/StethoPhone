package com.respiratory.lungaudio.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.util.AttributeSet;
import android.view.View;

import androidx.annotation.Nullable;

/**
 * Custom Android View for rendering the Time-Expanded Oscillogram Waveform.
 */
public class TimeExpandedWaveformView extends View {

    private double[] samples;
    private final Paint wavePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint gridPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path wavePath = new Path();

    public TimeExpandedWaveformView(Context context) {
        super(context);
        init();
    }

    public TimeExpandedWaveformView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        wavePaint.setStyle(Paint.Style.STROKE);
        wavePaint.setStrokeWidth(3f);
        wavePaint.setColor(0xFF3F51B5);

        gridPaint.setStyle(Paint.Style.STROKE);
        gridPaint.setStrokeWidth(1.5f);
        gridPaint.setColor(0x22000000);
    }

    public void setWaveData(double[] samples, boolean isAmplified) {
        this.samples = samples;
        wavePaint.setColor(isAmplified ? 0xFF3F51B5 : 0xFF00897B);
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float w = getWidth();
        float h = getHeight();
        float centerY = h / 2.0f;

        // Draw centerline and grid guides
        canvas.drawLine(0, centerY, w, centerY, gridPaint);
        canvas.drawLine(0, centerY * 0.5f, w, centerY * 0.5f, gridPaint);
        canvas.drawLine(0, centerY * 1.5f, w, centerY * 1.5f, gridPaint);

        if (samples == null || samples.length == 0) return;

        int numPoints = Math.min(samples.length, (int) (w * 2));
        double step = (double) samples.length / numPoints;
        float dx = w / numPoints;

        wavePath.reset();
        wavePath.moveTo(0, centerY);

        for (int i = 0; i < numPoints; i++) {
            int idx = Math.min(samples.length - 1, (int) (i * step));
            float s = (float) samples[idx];
            float x = i * dx;
            float y = centerY - (s * (centerY * 0.95f));
            wavePath.lineTo(x, y);
        }

        canvas.drawPath(wavePath, wavePaint);
    }
}
