package com.siteonlab.zopiq_live_card;

import android.app.Notification;
import android.os.Bundle;

import java.util.Collections;
import java.util.List;

/**
 * The Android 16 branch: a real {@code Notification.ProgressStyle}, promoted.
 *
 * <p>This is the only place in the module that names an API 36 class, and it is a class of its own
 * for a reason: the JVM resolves a type when the method referencing it is first verified, so keeping
 * these references behind a class boundary guarantees an Android 10 phone never loads them at all.
 * {@link LiveCardNotification} touches this only inside an {@code SDK_INT >= 36} guard.
 *
 * <p>What this buys over the bitmap every other Android gets:
 *
 * <ul>
 *   <li>the <b>status-bar chip</b> while the phone is in use — an OS surface with no equivalent
 *       below 16, and the one part of the live card that genuinely cannot be reproduced;
 *   <li>a guaranteed slot at the <b>top of the lock screen</b> and the always-on display, rather
 *       than wherever the shade decides to sort an ongoing notification;
 *   <li>a bar drawn by system UI, which <b>animates between two values</b> — so on this branch the
 *       twenty-second tick from {@link LiveCardService} is not a step but the start of a smooth
 *       glide to the next position.
 * </ul>
 */
final class PromotedStyle {

    private PromotedStyle() {}

    /**
     * The opt-in for promoted-ongoing treatment.
     *
     * <p>Spelled out rather than referenced as {@code Notification.EXTRA_REQUEST_PROMOTED_ONGOING}
     * so that the module keeps compiling if it is ever built against a lower {@code compileSdk};
     * the extras bundle is keyed by string either way.
     */
    private static final String EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing";

    /**
     * Attach the bar and the countdown, and ask to be promoted.
     *
     * <p><b>One segment, no points.</b> The style is built for a journey with named stops, and that
     * is what this used to be: three segments and a milestone dot at each boundary. 0055 made the
     * fill a continuous function of the clock, and punctuation on a bar that sweeps rather than
     * steps marks nothing — so it is now a single full-length segment, which is the style's way of
     * spelling "an ordinary progress bar, drawn by you, in our colour".
     *
     * <p>Deliberately does <b>not</b> call {@code Builder.setProgress}: the platform documents that
     * this style overrides those extras, so setting both is a way to be surprised later.
     *
     * <p>The countdown rides the notification header here rather than sitting under the bar, because
     * this branch may not carry custom {@code RemoteViews} — that is the price of promotion, and
     * {@code setUsesChronometer} is the standard template's own equivalent. Past the deadline it is
     * dropped entirely rather than left to count the overrun upward.
     *
     * <p>Asking is all an app can do. The OS applies its own eligibility rules on top — ongoing, a
     * content title, an eligible style, no custom {@code RemoteViews}, not colorized, not a group
     * summary, and a channel above {@code IMPORTANCE_MIN} — and {@link LiveCardNotification} is
     * built to satisfy every one of them on this branch.
     */
    static void apply(Notification.Builder builder, LiveCardSpec spec) {
        final List<Notification.ProgressStyle.Segment> segments =
                Collections.singletonList(
                        new Notification.ProgressStyle.Segment(100).setColor(Ladder.BRAND));

        builder.setStyle(
                new Notification.ProgressStyle()
                        .setProgress(spec.progressNow())
                        .setProgressSegments(segments));

        final long remaining = spec.remainingMs();
        if (remaining > 0L) {
            builder.setWhen(System.currentTimeMillis() + remaining)
                    .setUsesChronometer(true)
                    .setChronometerCountDown(true);
        } else {
            builder.setUsesChronometer(false);
        }

        final Bundle extras = new Bundle();
        extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true);
        builder.addExtras(extras);
    }
}
