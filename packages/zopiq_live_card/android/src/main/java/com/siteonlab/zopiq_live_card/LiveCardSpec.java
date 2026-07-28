package com.siteonlab.zopiq_live_card;

import android.content.Intent;
import android.text.TextUtils;

/**
 * One card, and everything needed to redraw it without asking anybody anything.
 *
 * <p>This is the class the whole redesign turns on. Migration 0055 stopped sending the device a
 * position and started sending a pair of instants; a spec is that pair plus the copy that goes
 * around it, and {@link #progressNow()} is the arithmetic in between. Because a spec is complete —
 * it holds absolute wall-clock instants, not "minutes remaining" computed when the push was built —
 * {@link LiveCardService} can redraw the bar every twenty seconds from a spec it received once, with
 * no network, no database and no Dart engine alive.
 *
 * <p>The window is <b>constant for the life of a phase</b> (0055 guarantees it: both ends derive
 * from timestamps already recorded). So {@link #progressNow()} is monotonic and the countdown can
 * only ever fall, which is Rule 3 holding without anything here having to enforce it.
 *
 * <p>Immutable, and travels as Intent extras rather than as a {@code Parcelable} — the only thing
 * that ever carries one is a start-service intent, and a hand-rolled flat bundle is both less code
 * and immune to the versioning trap of a Parcelable whose fields change between an app update and a
 * pending intent created by the version before it.
 */
final class LiveCardSpec {

    /** {@link #progressOverride} when the server sent none and the clock is in charge. */
    static final int NO_OVERRIDE = -1;

    private static final String EXTRA_PREFIX = "zopiq_live_";

    final int id;
    final String orderId;
    final String title;
    final String body;
    final String phase;
    final long windowStartMs;
    final long windowEndMs;
    final int progressOverride;

    LiveCardSpec(
            int id,
            String orderId,
            String title,
            String body,
            String phase,
            long windowStartMs,
            long windowEndMs,
            int progressOverride) {
        this.id = id;
        this.orderId = orderId == null ? "" : orderId;
        this.title = title == null ? "" : title;
        this.body = body;
        this.phase = Ladder.PHASE_DELIVERY.equals(phase) ? Ladder.PHASE_DELIVERY : Ladder.PHASE_PREP;
        this.windowStartMs = windowStartMs;
        this.windowEndMs = windowEndMs;
        this.progressOverride = progressOverride;
    }

    boolean isDelivery() {
        return Ladder.PHASE_DELIVERY.equals(phase);
    }

    /**
     * Where the bar should be, right now, on this device's clock.
     *
     * <p>An explicit override wins outright — today that is only {@code at_door} pinning the bar
     * full, but it is also the seam B3 will come through: once {@code rider_locations} exists the
     * server writes real distance-covered into that field and this method starts returning a
     * distance rather than a time, with nothing else in the module changing.
     *
     * <p>A window that is inverted or empty (a clock skewed far enough to put the phone past the
     * deadline before it started, a kitchen that promised a prep time already elapsed) yields 100
     * rather than a division by zero or a negative bar.
     */
    int progressNow() {
        if (progressOverride != NO_OVERRIDE) return Ladder.clampProgress(progressOverride);

        final long span = windowEndMs - windowStartMs;
        if (span <= 0L) return 100;

        final long elapsed = System.currentTimeMillis() - windowStartMs;
        if (elapsed <= 0L) return 0;

        return Ladder.clampProgress((int) (elapsed * 100L / span));
    }

    /** Milliseconds until the deadline, floored at zero. */
    long remainingMs() {
        final long remaining = windowEndMs - System.currentTimeMillis();
        return remaining > 0L ? remaining : 0L;
    }

    /**
     * The line along the top of the card.
     *
     * <p>It names the same instant the bar and the countdown below it are running to, which is the
     * point: a card that said "arriving in 31 min" above a bar measuring how long the kitchen has
     * left would be showing two different numbers for two different events and inviting the customer
     * to read one as the other. The prep card counts to the food being ready and says so; the
     * delivery card counts to the door.
     */
    String subText() {
        final long remaining = remainingMs();
        if (remaining <= 0L) {
            return isDelivery() ? "Arriving any moment" : "Ready any moment";
        }

        // Rounded up, so a card is never showing "0 min" while its own countdown still has seconds
        // on it.
        final long minutes = (remaining + 59_999L) / 60_000L;
        return (isDelivery() ? "Arriving in " : "Ready in ") + minutes + " min";
    }

    /**
     * True when two specs describe the same card in the same state, so a tick that would redraw the
     * card identically can be skipped. Only the fields that can change are compared; the window is
     * what makes {@link #progressNow()} move, so an unchanged window with unchanged progress is a
     * genuinely unchanged card.
     */
    boolean sameContentAs(LiveCardSpec other) {
        return other != null
                && id == other.id
                && phase.equals(other.phase)
                && title.equals(other.title)
                && TextUtils.equals(body, other.body)
                && windowStartMs == other.windowStartMs
                && windowEndMs == other.windowEndMs
                && progressOverride == other.progressOverride;
    }

    // ---------------------------------------------------------------- intent plumbing

    void writeTo(Intent intent) {
        intent.putExtra(EXTRA_PREFIX + "id", id)
                .putExtra(EXTRA_PREFIX + "orderId", orderId)
                .putExtra(EXTRA_PREFIX + "title", title)
                .putExtra(EXTRA_PREFIX + "body", body)
                .putExtra(EXTRA_PREFIX + "phase", phase)
                .putExtra(EXTRA_PREFIX + "windowStart", windowStartMs)
                .putExtra(EXTRA_PREFIX + "windowEnd", windowEndMs)
                .putExtra(EXTRA_PREFIX + "override", progressOverride);
    }

    /** Null when the intent carries no spec — a restarted service, or a bare cancel. */
    static LiveCardSpec readFrom(Intent intent) {
        if (intent == null || !intent.hasExtra(EXTRA_PREFIX + "id")) return null;
        return new LiveCardSpec(
                intent.getIntExtra(EXTRA_PREFIX + "id", 0),
                intent.getStringExtra(EXTRA_PREFIX + "orderId"),
                intent.getStringExtra(EXTRA_PREFIX + "title"),
                intent.getStringExtra(EXTRA_PREFIX + "body"),
                intent.getStringExtra(EXTRA_PREFIX + "phase"),
                intent.getLongExtra(EXTRA_PREFIX + "windowStart", 0L),
                intent.getLongExtra(EXTRA_PREFIX + "windowEnd", 0L),
                intent.getIntExtra(EXTRA_PREFIX + "override", NO_OVERRIDE));
    }
}
