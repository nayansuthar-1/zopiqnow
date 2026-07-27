package com.siteonlab.zopiq_live_card;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;

/**
 * The progress bar, drawn by hand, for every Android below 16.
 *
 * <p>Android 16 draws this itself from {@code Notification.ProgressStyle}. Below it the platform's
 * own {@code setProgress} bar cannot be themed, sized or rounded, so the bar is painted into a
 * bitmap and handed to an {@code ImageView} inside a {@code RemoteViews} body. That is the whole
 * reason this file exists, and it is why the card looks the same on an Android 10 phone as on an
 * Android 16 one.
 *
 * <p><b>One unbroken fill.</b> It used to be three segments with a milestone dot at each boundary
 * and a larger marker disc riding the head. All of that described a bar that moved in jumps, and
 * once 0055 made the fill a continuous function of the clock the punctuation stopped describing
 * anything — a dot at 35% is meaningless when the bar sweeps past it a pixel at a time. A plain
 * rounded track with a plain rounded fill is also what the reference design is.
 *
 * <p>Drawn on every tick of {@link LiveCardService} — roughly three times a minute for the life of
 * an order — which is why the bitmap is deliberately small and the paint objects are the only
 * allocations.
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
     * the ImageView scales the difference back up. A 6dp bar upscaled by a third is not something an
     * eye finds, and it keeps the card well clear of a {@code TransactionTooLargeException}. It
     * matters more now than it did: this crosses that Binder every twenty seconds, not eight times
     * an order.
     */
    private static final float MAX_SCALE = 720f / WIDTH_DP;

    private static final float BAR_DP = 6f;

    static Bitmap render(Context context, int progress) {
        final float scale =
                Math.min(context.getResources().getDisplayMetrics().density, MAX_SCALE);
        final int clamped = Ladder.clampProgress(progress);

        final float width = WIDTH_DP * scale;
        final float height = BAR_DP * scale;
        final float radius = height / 2f;

        final Bitmap bitmap =
                Bitmap.createBitmap(
                        Math.round(width), Math.round(height), Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(bitmap);
        final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

        // 1. The track, end to end.
        paint.setColor(Ladder.TRACK);
        canvas.drawRoundRect(new RectF(0f, 0f, width, height), radius, radius, paint);

        // 2. The distance covered. Below one bar-width the rounded rect would be drawn as a lens
        //    thinner than the track it sits in, which reads as a rendering fault rather than as
        //    "barely started" — so the fill either has a full round cap or is not drawn at all.
        final float head = width * (clamped / 100f);
        if (head >= height) {
            paint.setColor(Ladder.BRAND);
            canvas.drawRoundRect(new RectF(0f, 0f, head, height), radius, radius, paint);
        }

        return bitmap;
    }
}
