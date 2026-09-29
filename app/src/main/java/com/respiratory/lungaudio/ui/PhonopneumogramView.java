package com.respiratory.lungaudio.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.util.AttributeSet;
import android.view.View;

import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.List;

/**
 * Custom Android View for rendering the Phonopneumogram (Acoustic Respiratory PPG) tidal waveform.
 */
public class PhonopneumogramView extends View {

    private double[] envelope;
    private List<Integer> peakIndices = new ArrayList<>();

    private final Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint peakPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint peakInnerPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path wavePath = new Path();
    private final Path fillPath = new Path();

    public PhonopneumogramView(Context context) {
        super(context);
        init();
    }

    public PhonopneumogramView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        strokePaint.setStyle(Paint.Style.STROKE);
        strokePaint.setStrokeWidth(5f);
        strokePaint.setColor(0xFF00897B);

        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setColor(0x3300897B);

        peakPaint.setStyle(Paint.Style.FILL);
        peakPaint.setColor(0xFFE53935);

        peakInnerPaint.setStyle(Paint.Style.FILL);
        peakInnerPaint.setColor(Color.WHITE);
    }

    public void setPpgData(double[] envelope, List<Integer> peakIndices) {
        this.envelope = envelope;
        this.peakIndices = peakIndices != null ? peakIndices : new ArrayList<>();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (envelope == null || envelope.length < 2) return;

        float w = getWidth();
        float h = getHeight();
        float dx = w / (envelope.length - 1);

        wavePath.reset();
        fillPath.reset();

        float startY = h - ((float) envelope[0] * (h - 20f));
        wavePath.moveTo(0, startY);
        fillPath.moveTo(0, h);
        fillPath.lineTo(0, startY);

        for (int i = 1; i < envelope.length; i++) {
            float x = i * dx;
            float y = h - ((float) envelope[i] * (h - 20f));
            wavePath.lineTo(x, y);
            fillPath.lineTo(x, y);
        }

        fillPath.lineTo(w, h);
        fillPath.close();

        canvas.drawPath(fillPath, fillPaint);
        canvas.drawPath(wavePath, strokePaint);

        // Draw breath peaks (Inspiratory & Expiratory peaks)
        for (int idx : peakIndices) {
            if (idx < envelope.length) {
                float px = idx * dx;
                float py = h - ((float) envelope[idx] * (h - 20f));
                canvas.drawCircle(px, py, 10f, peakPaint);
                canvas.drawCircle(px, py, 4f, peakInnerPaint);
            }
        }
    }
}
