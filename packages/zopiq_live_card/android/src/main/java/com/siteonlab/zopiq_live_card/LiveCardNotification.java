package com.siteonlab.zopiq_live_card;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.SystemClock;
import android.text.TextUtils;
import android.view.View;
import android.widget.RemoteViews;

/**
 * The live order card, built once and drawn two ways.
 *
 * <p>The split is not a preference. Android 16's promoted-ongoing rules disqualify any notification
 * carrying custom {@code RemoteViews}, and every Android below 16 has no {@code ProgressStyle} to
 * draw. So the two are mutually exclusive by construction, and the bar is reproduced by hand
 * wherever the OS will not draw one:
 *
 * <ul>
 *   <li><b>API 36+</b> — {@link PromotedStyle}: a real progress bar, the status-bar chip and a
 *       guaranteed slot at the top of the lock screen, with the countdown in the system header.
 *   <li><b>API 24–35</b> — {@code DecoratedCustomViewStyle} over {@link TrackerBar}: the same bar,
 *       painted into a bitmap, with the countdown as a {@code Chronometer} beneath it, on the
 *       Android 10 floor.
 * </ul>
 *
 * <p><b>Two cards, not one.</b> An order now produces a prep card that fills while the kitchen cooks
 * and a separate delivery card that starts empty at pickup — different notification ids, different
 * artwork, different windows. {@link LiveCardService} owns the clock that moves them; this class
 * only ever renders a {@link LiveCardSpec} at the instant it is asked to.
 *
 * <p><b>Why the countdown is a Chronometer and not text.</b> A {@code Chronometer} in countdown mode
 * is ticked by the system UI process at no cost to this app, so the seconds under the bar keep
 * falling between service ticks and stay right even if a tick is delayed by Doze. The bar needs a
 * redraw to move; the number does not.
 */
final class LiveCardNotification {

    private LiveCardNotification() {}

    static final String CHANNEL_ID = "order_live";
    /**
     * How close to its deadline a countdown gets before it is replaced by plain text.
     *
     * <p>See the use site: a {@code Chronometer} does not stop at zero, so the last second is
     * given up rather than risk rendering a negative one.
     */
    private static final long COUNTDOWN_RETIRE_MS = 1_000L;

    private static final String CHANNEL_NAME = "Live order tracking";
    private static final String CHANNEL_DESCRIPTION = "The live card while an order is on its way.";

    /** The order a tap on the card is asking to open. Read back by {@link ZopiqLiveCardPlugin}. */
    static final String EXTRA_ORDER_ID = "zopiq_live_card_order_id";

    static void show(Context context, LiveCardSpec spec) {
        final NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return;
        ensureChannel(manager);
        manager.notify(spec.id, build(context, spec));
    }

    static void cancel(Context context, int notificationId) {
        final NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) manager.cancel(notificationId);
    }

    /**
     * Render a spec into a notification.
     *
     * <p>Separate from {@link #show} because {@link LiveCardService} needs the {@code Notification}
     * object itself to hand to {@code startForeground}, not a posted one.
     */
    static Notification build(Context context, LiveCardSpec spec) {
        ensureChannel(context.getSystemService(NotificationManager.class));

        final Notification.Builder builder = newBuilder(context);
        builder.setSmallIcon(context.getApplicationInfo().icon)
                .setColor(Ladder.BRAND)
                .setContentTitle(spec.title)
                .setContentText(spec.body)
                .setSubText(spec.subText())
                // Sits in the shade for the life of the order, and a tap means "show me", not
                // "I'm done with this".
                .setOngoing(true)
                .setAutoCancel(false)
                // Many redraws, one alert. The order's noisy half is the `order_updates` channel.
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(tapIntent(context, spec.id, spec.orderId));

        // `setColorized` is deliberately absent. A colorized notification is ineligible for Android
        // 16 promotion, and the platform honours it only for foreground-service and media
        // notifications anyway. `setColor` still tints the icon and accents orange.

        applyCustomTracker(context, builder, spec);

        return builder.build();
    }

    /**
     * The image on the right of the card: food while the kitchen cooks, a rider once the food is on
     * a bike.
     *
     * <p><b>A direct {@code R.drawable} reference, and that is the entire point of this method.</b>
     * These used to be looked up by name with {@code Resources.getIdentifier} out of the host app's
     * resources, so that the app could own its own brand assets. It worked in debug and produced the
     * stock Flutter launcher icon in release, because a resource whose only mention is a string
     * passed to {@code getIdentifier} — from a different module, at that — is a resource
     * {@code shrinkResources} cannot see anybody using, and it was stripped from the APK. The
     * fallback to {@code getApplicationInfo().icon} then hid the failure behind something that
     * looked deliberate.
     *
     * <p>A direct reference is a hard reference: the shrinker keeps it, the compiler checks it, and
     * there is no fallback path left to hide behind. The host app can still override either image
     * simply by shipping a drawable of the same name — resource merging gives the application's copy
     * precedence over this module's — and because the reference below is what is kept, the app's
     * copy is now reachable rather than shrunk away.
     */
    private static int artworkResId(LiveCardSpec spec) {
        return spec.isDelivery() ? R.drawable.zopiq_live_delivery : R.drawable.zopiq_live_prep;
    }

    /**
     * The card for every Android that will not draw a progress bar itself.
     *
     * <p>{@code DecoratedCustomViewStyle} keeps the system's own header — app icon, app name, the
     * "Arriving in 18 min" sub-text, the artwork, the expander — and replaces only the body. That is
     * what lets a hand-built layout inherit the shade's light or dark theme instead of guessing at
     * it, and it is why the layouts in {@code res/layout} are a few views rather than a whole
     * notification.
     *
     * <p><b>No {@code setProgress}.</b> It used to be set as well, on the theory that the decorated
     * body hid it and that an OEM shell or a Wear companion declining to render custom views would
     * fall back to the standard template and at least have a bar there. It does not hide it: on
     * Android 15 the platform draws its own thin bar underneath the custom body, so the card had two
     * progress bars — ours, and a second one in the system accent colour saying the same thing a
     * few pixels lower. One bar is the design; a hypothetical Wear fallback is not worth a visible
     * duplicate on every phone that actually exists.
     */
    private static void applyCustomTracker(
            Context context, Notification.Builder builder, LiveCardSpec spec) {

        final android.graphics.Bitmap bar = TrackerBar.render(context, spec.progressNow());
        final String packageName = context.getPackageName();
        final int artworkId = artworkResId(spec);

        final RemoteViews collapsed = new RemoteViews(packageName, R.layout.zopiq_live_card);
        dress(collapsed, spec, bar, artworkId);

        final RemoteViews expanded =
                new RemoteViews(packageName, R.layout.zopiq_live_card_expanded);
        dress(expanded, spec, bar, artworkId);
        if (TextUtils.isEmpty(spec.body)) {
            expanded.setViewVisibility(R.id.zopiq_live_body, View.GONE);
        } else {
            expanded.setTextViewText(R.id.zopiq_live_body, spec.body);
        }

        builder.setStyle(new Notification.DecoratedCustomViewStyle());
        builder.setCustomContentView(collapsed);
        builder.setCustomBigContentView(expanded);
    }

    /**
     * Fill the parts both layouts share: the headline, the bar, and the countdown under it.
     *
     * <p>The countdown is two views in one slot. A {@code Chronometer} ticks the seconds down for
     * free while there is time left; past the deadline it would start counting the overrun back up,
     * which is a card telling the customer how late their food is — so at zero it is swapped for a
     * plain line of text and the clock stops being mentioned at all.
     */
    private static void dress(
            RemoteViews views, LiveCardSpec spec, android.graphics.Bitmap bar, int artworkResId) {
        views.setTextViewText(R.id.zopiq_live_title, spec.title);
        views.setImageViewBitmap(R.id.zopiq_live_tracker, bar);
        views.setImageViewResource(R.id.zopiq_live_artwork, artworkResId);

        final long remaining = spec.remainingMs();
        // Not `> 0`. The redraw is scheduled to land exactly on the deadline, but a Handler is
        // allowed to be late, and a Chronometer whose base has already passed paints the overshoot
        // as a negative time — "-00:02", counting downward, on somebody's lock screen. Retiring it
        // a second early costs a second of an already-rounded countdown and makes that impossible.
        if (remaining > COUNTDOWN_RETIRE_MS) {
            views.setViewVisibility(R.id.zopiq_live_countdown, View.VISIBLE);
            views.setViewVisibility(R.id.zopiq_live_countdown_done, View.GONE);
            // The Chronometer timebase is elapsedRealtime, not wall clock.
            views.setChronometer(
                    R.id.zopiq_live_countdown,
                    SystemClock.elapsedRealtime() + remaining,
                    null,
                    true);
            views.setChronometerCountDown(R.id.zopiq_live_countdown, true);
        } else {
            views.setViewVisibility(R.id.zopiq_live_countdown, View.GONE);
            views.setViewVisibility(R.id.zopiq_live_countdown_done, View.VISIBLE);
            views.setTextViewText(R.id.zopiq_live_countdown_done, spec.subText());
        }
    }

    /**
     * Open the app on the order this card belongs to.
     *
     * <p>The launcher intent rather than a hard-coded activity name, because this module is a
     * package and has no business knowing what the host app calls its entry point. {@code
     * FLAG_UPDATE_CURRENT} matters: without it a second tick would reuse the first tick's extras,
     * which is harmless here only because the order id never changes — and would stop being harmless
     * the moment anything else went in the bundle.
     */
    private static PendingIntent tapIntent(Context context, int notificationId, String orderId) {
        final Intent launch =
                context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launch == null) return null;

        launch.putExtra(EXTRA_ORDER_ID, orderId);
        launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);

        return PendingIntent.getActivity(
                context,
                // Per notification, so an order's two cards cannot collapse onto one intent.
                notificationId,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /**
     * Sound and vibration are off on the channel itself, not merely on each notification: the
     * channel is what the customer sees in system settings, and it should read there as the silent
     * tracker it is. {@code IMPORTANCE_DEFAULT} rather than HIGH so the card never peeks over what
     * they are doing — and rather than LOW because {@code IMPORTANCE_MIN} would make it ineligible
     * for Android 16 promotion and LOW is one step from it.
     *
     * <p>Creating a channel that already exists is a no-op, so this runs on every tick without
     * fighting any change the customer has made to it.
     */
    private static void ensureChannel(NotificationManager manager) {
        if (manager == null) return;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        final NotificationChannel channel =
                new NotificationChannel(
                        CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription(CHANNEL_DESCRIPTION);
        channel.setSound(null, null);
        channel.enableVibration(false);
        channel.setShowBadge(false);
        manager.createNotificationChannel(channel);
    }

    @SuppressWarnings("deprecation")
    private static Notification.Builder newBuilder(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return new Notification.Builder(context, CHANNEL_ID);
        }
        // Android 7.x only. Channels do not exist there; priority is the whole story.
        return new Notification.Builder(context).setPriority(Notification.PRIORITY_DEFAULT);
    }
}
