package com.siteonlab.zopiq_live_card;

/**
 * The shape of the tracker, in one place.
 *
 * <p>Migration 0052 hands the device a single {@code progress} number, taken as the furthest point
 * either the kitchen ladder ({@code orders.status}) or the road ladder ({@code deliveries.state})
 * has reached. This class is where that number becomes a picture, and both drawing paths — the
 * Android 16 {@code ProgressStyle} and the bitmap every older Android gets — read the milestones
 * from here, so the two can never drift into showing different trackers.
 *
 * <p>The three milestones are the ones a customer actually holds in their head. They are
 * deliberately fewer than the eight steps the server emits: {@code accepted} (15), {@code claimed}
 * (20), {@code packed} (55), {@code rider_at_restaurant} (65) and {@code at_door} (95) all move the
 * bar without earning a dot of their own, which is what stops the tracker reading as a progress bar
 * with a rash.
 */
final class Ladder {

    private Ladder() {}

    /** Swiggy orange, {@code ZopiqPalette.primary}. */
    static final int BRAND = 0xFFFC8019;

    /**
     * The unfilled track, and the milestones not yet reached.
     *
     * <p>Half-transparent grey rather than a fixed colour: a notification is drawn on a background
     * this module cannot read — white on a light theme, near-black on a dark one — and only an
     * alpha-blended neutral reads correctly on both.
     */
    static final int TRACK = 0x40808080;

    /**
     * Milestone positions on the 0–100 scale: the kitchen starts cooking, the food leaves with a
     * rider, the food arrives.
     */
    static final int[] POINTS = {35, 75, 100};

    /**
     * The same three milestones expressed as segment lengths, which is the form
     * {@code Notification.ProgressStyle} wants. Sums to 100.
     */
    static final int[] SEGMENTS = {35, 40, 25};

    static int clampProgress(int progress) {
        if (progress < 0) return 0;
        return Math.min(progress, 100);
    }
}
