package com.siteonlab.zopiq_live_card;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RectF;

/**
 * The segmented tracker, drawn by hand, for every Android below 16.
 *
 * <p>Android 16 draws this itself from {@code Notification.ProgressStyle}. Below it the platform
 * offers exactly one shape — {@code setProgress}, a plain unbroken bar — so the segments and
 * milestone dots have to be painted into a bitmap and handed to an {@code ImageView} inside a
 * {@code RemoteViews} body. That is the whole reason this file exists, and it is why the card looks
 * the same on an Android 10 phone as on an Android 16 one.
 *
 * <p>Drawn once per notification update, which is at most eight times over an order's life, so the
 * allocation is not worth pooling.
 */
final class TrackerBar {

    private TrackerBar() {}

    /** Logical width. The ImageView scales this to whatever the shade is; only the ratio matters. */
    private static final float WIDTH_DP = 320f;

    /**
     * A ceiling on the rendered scale, and not a cosmetic one.
     *
     * <p>A bitmap in a {@code RemoteViews} crosses to system_server through a Binder transaction
     * with about a megabyte to spend, and this one is sent twice — once for the collapsed body, once
     * for the expanded. At density 3 an unclamped bar would be 960px wide; clamped it is 720px, and
     * the ImageView scales the difference back up. A 5dp bar upscaled by a third is not something an
     * eye finds, and it keeps the card well clear of a {@code TransactionTooLargeException}.
     */
    private static final float MAX_SCALE = 720f / WIDTH_DP;

    private static final float BAR_DP = 5f;
    private static final float DOT_RADIUS_DP = 4.5f;
    private static final float MARKER_RADIUS_DP = 6f;

    /**
     * The break between two segments. Cut out of the bar rather than painted over it, because the
     * notification background behind it is unknown — see {@link Ladder#TRACK}.
     */
    private static final float GAP_DP = 3.5f;

    static Bitmap render(Context context, int progress) {
        final float scale =
                Math.min(context.getResources().getDisplayMetrics().density, MAX_SCALE);
        final int clamped = Ladder.clampProgress(progress);

        final float width = WIDTH_DP * scale;
        final float bar = BAR_DP * scale;
        final float dot = DOT_RADIUS_DP * scale;
        final float marker = MARKER_RADIUS_DP * scale;
        final float gap = GAP_DP * scale;

        // The marker is the tallest thing on the bar, so it sets the height and the horizontal
        // inset: without the inset the dot at 100 would be sliced in half by the right edge.
        final float height = marker * 2f;
        final float inset = marker;
        final float midY = height / 2f;
        final float span = width - inset * 2f;

        final Bitmap bitmap =
                Bitmap.createBitmap(Math.round(width), Math.round(height), Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(bitmap);
        final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

        final float top = midY - bar / 2f;
        final float bottom = midY + bar / 2f;
        final float radius = bar / 2f;

        // 1. The track, end to end.
        paint.setColor(Ladder.TRACK);
        canvas.drawRoundRect(new RectF(inset, top, width - inset, bottom), radius, radius, paint);

        // 2. The distance covered.
        final float head = inset + span * (clamped / 100f);
        if (clamped > 0) {
            paint.setColor(Ladder.BRAND);
            canvas.drawRoundRect(new RectF(inset, top, head, bottom), radius, radius, paint);
        }

        // 3. The segment breaks, cut clean through both. CLEAR against a transparent bitmap is what
        //    lets the shade's own background show through the gap, on a light theme and a dark one
        //    alike — painting a "background-coloured" bar there would guess wrong on one of them.
        paint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));
        int boundary = 0;
        for (int i = 0; i < Ladder.SEGMENTS.length - 1; i++) {
            boundary += Ladder.SEGMENTS[i];
            final float x = inset + span * (boundary / 100f);
            canvas.drawRect(x - gap / 2f, top, x + gap / 2f, bottom, paint);
        }
        paint.setXfermode(null);

        // 4. The milestones. Filled once passed, hollow-grey until then — the same two-state dot the
        //    Android 16 ProgressStyle points draw for themselves.
        for (final int point : Ladder.POINTS) {
            paint.setColor(clamped >= point ? Ladder.BRAND : Ladder.TRACK);
            canvas.drawCircle(inset + span * (point / 100f), midY, dot, paint);
        }

        // 5. Where the order is right now. A solid disc, larger than a milestone and nothing more:
        //    no halo, no glow (zopiqnow-clean-ui). At 100 it lands on the last milestone and simply
        //    reads as a filled end.
        paint.setColor(Ladder.BRAND);
        canvas.drawCircle(head, midY, marker, paint);

        return bitmap;
    }
}
