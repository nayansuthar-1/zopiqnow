package com.siteonlab.zopiq_live_card;

import android.app.Notification;
import android.os.Bundle;

import java.util.ArrayList;
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
 *   <li>segments and milestone points drawn by system UI, so they animate and match the device
 *       theme instead of being a picture we painted.
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
     * Attach the segmented tracker and ask to be promoted.
     *
     * <p>Deliberately does <b>not</b> call {@code Builder.setProgress}: the platform documents that
     * this style overrides those extras, so setting both is a way to be surprised later.
     *
     * <p>Asking is all an app can do. The OS applies its own eligibility rules on top — ongoing, a
     * content title, an eligible style, no custom {@code RemoteViews}, not colorized, not a group
     * summary, and a channel above {@code IMPORTANCE_MIN} — and {@link LiveCardNotification} is
     * built to satisfy every one of them on this branch.
     */
    static void apply(Notification.Builder builder, int progress) {
        final List<Notification.ProgressStyle.Segment> segments = new ArrayList<>();
        for (final int length : Ladder.SEGMENTS) {
            segments.add(new Notification.ProgressStyle.Segment(length).setColor(Ladder.BRAND));
        }

        final List<Notification.ProgressStyle.Point> points = new ArrayList<>();
        for (final int position : Ladder.POINTS) {
            // The last milestone is the end of the bar. A point sitting on the terminus reads as a
            // smudge rather than a step, so the ladder's 100 is left to the bar itself.
            if (position >= 100) continue;
            points.add(new Notification.ProgressStyle.Point(position).setColor(Ladder.BRAND));
        }

        builder.setStyle(
                new Notification.ProgressStyle()
                        // Segment lengths sum to 100, which is the scale migration 0052 sends.
                        .setProgress(Ladder.clampProgress(progress))
                        .setProgressSegments(segments)
                        .setProgressPoints(points));

        final Bundle extras = new Bundle();
        extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true);
        builder.addExtras(extras);
    }
}
