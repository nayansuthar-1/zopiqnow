package com.siteonlab.zopiq_live_card;

/**
 * The look of the tracker, and the two phases it is drawn for.
 *
 * <p><b>What used to be here.</b> Milestones. Migration 0052 handed the device one number on a
 * ladder of eight server-side steps, and this class turned it into three segments with a dot at each
 * boundary. The bar therefore moved only when the kitchen or the rider pressed something: it sat
 * still for twenty minutes and then jumped forty points. Migration 0055 replaced the ladder with a
 * window — two instants the device interpolates between — so there is no longer any such thing as a
 * milestone position, and the segments and points that expressed them are gone with it.
 *
 * <p>What is left is colour, and the names of the two cards an order now gets.
 */
final class Ladder {

    private Ladder() {}

    /** Swiggy orange, {@code ZopiqPalette.primary}. */
    static final int BRAND = 0xFFFC8019;

    /**
     * The unfilled track.
     *
     * <p>Half-transparent grey rather than a fixed colour: a notification is drawn on a background
     * this module cannot read — white on a light theme, near-black on a dark one — and only an
     * alpha-blended neutral reads correctly on both.
     */
    static final int TRACK = 0x40808080;

    /** The kitchen is cooking. The bar fills against the prep window. */
    static final String PHASE_PREP = "prep";

    /** The food is on a bike. The bar fills against the ride window. */
    static final String PHASE_DELIVERY = "delivery";

    static int clampProgress(int progress) {
        if (progress < 0) return 0;
        return Math.min(progress, 100);
    }
}
