package com.siteonlab.zopiq_live_card;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.text.TextUtils;
import android.view.View;
import android.widget.RemoteViews;

/**
 * The live order card, built once and drawn two ways.
 *
 * <p>The split is not a preference. Android 16's promoted-ongoing rules disqualify any notification
 * carrying custom {@code RemoteViews}, and every Android below 16 has no {@code ProgressStyle} to
 * draw. So the two are mutually exclusive by construction, and the tracker is reproduced with a
 * hand-painted bar wherever the OS will not draw one:
 *
 * <ul>
 *   <li><b>API 36+</b> — {@link PromotedStyle}: real segments, real milestone points, the status-bar
 *       chip and a guaranteed slot at the top of the lock screen.
 *   <li><b>API 24–35</b> — {@code DecoratedCustomViewStyle} over {@link TrackerBar}: the same
 *       segmented tracker, painted into a bitmap, on the Android 10 floor.
 * </ul>
 *
 * <p>Everything else is shared and unchanged from Tier 1 — one notification per order redrawn in
 * place, a silent channel, and a card that vanishes when the order ends.
 */
final class LiveCardNotification {

    private LiveCardNotification() {}

    static final String CHANNEL_ID = "order_live";
    private static final String CHANNEL_NAME = "Live order tracking";
    private static final String CHANNEL_DESCRIPTION = "The live card while an order is on its way.";

    /** The order a tap on the card is asking to open. Read back by {@link ZopiqLiveCardPlugin}. */
    static final String EXTRA_ORDER_ID = "zopiq_live_card_order_id";

    private static final int API_PROGRESS_STYLE = 36;

    static void show(
            Context context,
            int notificationId,
            String orderId,
            String title,
            String body,
            String subText,
            int progress) {

        final NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return;

        ensureChannel(manager);

        final Notification.Builder builder = newBuilder(context);
        builder.setSmallIcon(context.getApplicationInfo().icon)
                .setLargeIcon(Icon.createWithResource(context, context.getApplicationInfo().icon))
                .setColor(Ladder.BRAND)
                .setContentTitle(title)
                .setContentText(body)
                .setSubText(subText)
                // Sits in the shade for the life of the order, and a tap means "show me", not
                // "I'm done with this".
                .setOngoing(true)
                .setAutoCancel(false)
                // Eight redraws, one alert. The order's noisy half is the `order_updates` channel.
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(tapIntent(context, notificationId, orderId));

        // `setColorized` is deliberately absent, and this is the one visible change from Tier 1.
        // A colorized notification is ineligible for Android 16 promotion, and it was never doing
        // much anyway — the platform honours it only for foreground-service and media
        // notifications, which this is neither. `setColor` still tints the icon and accents orange.

        if (Build.VERSION.SDK_INT >= API_PROGRESS_STYLE) {
            PromotedStyle.apply(builder, progress);
        } else {
            applyCustomTracker(context, builder, title, body, progress);
        }

        manager.notify(notificationId, builder.build());
    }

    static void cancel(Context context, int notificationId) {
        final NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) manager.cancel(notificationId);
    }

    /**
     * The tracker for every Android that will not draw one itself.
     *
     * <p>{@code DecoratedCustomViewStyle} keeps the system's own header — app icon, app name, the
     * "Arriving in 18 min" sub-text, the expander — and replaces only the body. That is what lets a
     * hand-built layout inherit the shade's light or dark theme instead of guessing at it, and it is
     * why the layouts in {@code res/layout} are two views rather than a whole notification.
     *
     * <p>{@code setProgress} is set as well even though the decorated body hides it: an OEM shell,
     * Android Auto or a Wear companion that declines to render custom views falls back to the
     * standard template, and there it is the difference between a progress bar and nothing.
     */
    private static void applyCustomTracker(
            Context context, Notification.Builder builder, String title, String body, int progress) {

        final int clamped = Ladder.clampProgress(progress);
        builder.setProgress(100, clamped, false);

        final android.graphics.Bitmap bar = TrackerBar.render(context, clamped);
        final String packageName = context.getPackageName();

        final RemoteViews collapsed = new RemoteViews(packageName, R.layout.zopiq_live_card);
        collapsed.setTextViewText(R.id.zopiq_live_title, title);
        collapsed.setImageViewBitmap(R.id.zopiq_live_tracker, bar);

        final RemoteViews expanded =
                new RemoteViews(packageName, R.layout.zopiq_live_card_expanded);
        expanded.setTextViewText(R.id.zopiq_live_title, title);
        expanded.setImageViewBitmap(R.id.zopiq_live_tracker, bar);
        if (TextUtils.isEmpty(body)) {
            expanded.setViewVisibility(R.id.zopiq_live_body, View.GONE);
        } else {
            expanded.setTextViewText(R.id.zopiq_live_body, body);
        }

        builder.setStyle(new Notification.DecoratedCustomViewStyle());
        builder.setCustomContentView(collapsed);
        builder.setCustomBigContentView(expanded);
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
                // Per notification, so two running orders cannot collapse onto one intent.
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
