package com.siteonlab.zopiq_live_card;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The clock behind the bar.
 *
 * <p>A notification is a still picture: nothing about posting one makes it move afterwards. The
 * server sends at most a handful of events over an order's life, so a bar driven by pushes alone is
 * exactly the bar that used to jump forty points at a time. Something on the device has to redraw
 * it, and for the bar to keep creeping while the phone is locked and the app has been reclaimed,
 * that something has to be a foreground service. This is it.
 *
 * <p><b>It costs nothing to run.</b> A tick is arithmetic on two {@code long}s ({@link
 * LiveCardSpec#progressNow()}), a bitmap a few hundred pixels wide, and a {@code notify}. No
 * network, no database, no Flutter engine — a spec is self-contained precisely so this loop never
 * has to ask anyone anything. It exists only while an order is live and stops itself the moment the
 * last card is taken down.
 *
 * <p><b>The seconds are not its job.</b> The countdown under the bar is a {@code Chronometer} ticked
 * by system UI, so the number stays right between ticks and stays right even if Doze delays one.
 * This service moves the bar and refreshes the wording; twenty seconds is chosen against the bar's
 * own resolution — a 20-minute prep window advances about 1.7% per tick, which on a 320dp bar is
 * roughly five pixels, small enough to read as a creep rather than a step. On Android 16 it is
 * genuinely smooth, because system UI animates {@code ProgressStyle} between two values.
 */
public final class LiveCardService extends Service {

    private static final String TAG = "ZopiqLiveCard";

    private static final String ACTION_SHOW = "com.siteonlab.zopiq_live_card.SHOW";
    private static final String ACTION_CANCEL = "com.siteonlab.zopiq_live_card.CANCEL";
    private static final String EXTRA_CANCEL_ID = "cancel_id";

    private static final long TICK_MS = 20_000L;

    /**
     * How long past its own deadline a card may linger before this service forgets it.
     *
     * <p>Orders normally end with a `delivered` or `ended` push that cancels the card explicitly.
     * This is for the ones that do not: an order abandoned mid-flight, a push that never arrived.
     * Without it a single lost message would leave a foreground service ticking on a customer's
     * phone until they rebooted, which is a battery complaint with our name on it.
     */
    private static final long STALE_AFTER_MS = 2L * 60L * 60L * 1000L;

    /** Live cards by notification id. Insertion-ordered, so promotion picks the oldest. */
    private final Map<Integer, LiveCardSpec> cards = new LinkedHashMap<>();

    private final Handler handler = new Handler(Looper.getMainLooper());

    /** The card currently standing as the service's foreground notification. */
    private int foregroundId;

    private final Runnable tick =
            new Runnable() {
                @Override
                public void run() {
                    redrawAll();
                    if (!cards.isEmpty()) handler.postDelayed(this, TICK_MS);
                }
            };

    // ---------------------------------------------------------------- the way in

    /**
     * Post or redraw a card, and keep it ticking.
     *
     * <p>The card is drawn <b>first</b>, directly, and only then is the service asked to take it
     * over. That order is deliberate: starting a foreground service from the background is
     * restricted on Android 12+, and while a high-priority FCM message — which is what every
     * {@code order_live} push is — buys a temporary exemption, it is an exemption and not a
     * guarantee. Drawing first means the worst case is a correct card that steps on pushes instead
     * of creeping, rather than no card at all.
     */
    static void show(Context context, LiveCardSpec spec) {
        LiveCardNotification.show(context, spec);

        final Intent intent = new Intent(context, LiveCardService.class).setAction(ACTION_SHOW);
        spec.writeTo(intent);
        launch(context, intent);
    }

    /** Take a card down, and stop the service if it was the last one. */
    static void cancel(Context context, int notificationId) {
        LiveCardNotification.cancel(context, notificationId);

        final Intent intent =
                new Intent(context, LiveCardService.class)
                        .setAction(ACTION_CANCEL)
                        .putExtra(EXTRA_CANCEL_ID, notificationId);
        launch(context, intent);
    }

    /**
     * A cancel must never start a service that was not already running — it would be a service
     * spun up solely to be told to stop, and on Android 12+ that start is the one most likely to
     * be refused. {@code startService} is used for it, which is a no-op when nothing is running.
     */
    private static void launch(Context context, Intent intent) {
        final boolean show = ACTION_SHOW.equals(intent.getAction());
        try {
            if (show && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
        } catch (Exception e) {
            // ForegroundServiceStartNotAllowedException (API 31+), or a plain
            // IllegalStateException below it. The card is already on screen either way; all that is
            // lost is the creep between pushes.
            Log.w(TAG, "Live card ticker not started: " + e);
        }
    }

    // ---------------------------------------------------------------- lifecycle

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        final String action = intent == null ? null : intent.getAction();

        if (ACTION_CANCEL.equals(action)) {
            remove(intent.getIntExtra(EXTRA_CANCEL_ID, 0));
            return START_NOT_STICKY;
        }

        final LiveCardSpec spec = LiveCardSpec.readFrom(intent);
        if (spec == null) {
            // Restarted by the system with no intent, or handed something malformed. There is
            // nothing to tick and no notification to stand behind, and a foreground service that
            // cannot call startForeground must not stay up.
            stopEverything();
            return START_NOT_STICKY;
        }

        cards.put(spec.id, spec);
        promote(spec);
        schedule();
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacks(tick);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ---------------------------------------------------------------- the loop

    private void schedule() {
        handler.removeCallbacks(tick);
        if (!cards.isEmpty()) handler.postDelayed(tick, TICK_MS);
    }

    private void redrawAll() {
        final NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) return;

        final long now = System.currentTimeMillis();

        for (final Map.Entry<Integer, LiveCardSpec> entry :
                new LinkedHashMap<>(cards).entrySet()) {
            final LiveCardSpec spec = entry.getValue();

            if (now - spec.windowEndMs > STALE_AFTER_MS) {
                LiveCardNotification.cancel(this, spec.id);
                remove(spec.id);
                continue;
            }

            try {
                manager.notify(spec.id, LiveCardNotification.build(this, spec));
            } catch (Exception e) {
                Log.w(TAG, "Live card redraw failed: " + e);
            }
        }
    }

    // ---------------------------------------------------------------- foreground bookkeeping

    /**
     * Make a card the service's foreground notification, if it has not got one.
     *
     * <p>A foreground service stands behind exactly one notification. An order's prep and delivery
     * cards never overlap, so in the ordinary case there is only ever one candidate; two concurrent
     * orders mean the first one to arrive holds the slot and the second is posted normally. Both
     * still tick — the slot decides which notification the OS ties the service's lifetime to, not
     * which ones get redrawn.
     */
    private void promote(LiveCardSpec spec) {
        if (foregroundId != 0 && cards.containsKey(foregroundId)) return;

        final Notification notification = LiveCardNotification.build(this, spec);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                        spec.id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            } else {
                startForeground(spec.id, notification);
            }
            foregroundId = spec.id;
        } catch (Exception e) {
            // API 31+ can refuse the start outright. The notification is already posted by
            // `show`, so the card is correct; this service simply will not survive the app being
            // reclaimed.
            Log.w(TAG, "Live card foreground promotion refused: " + e);
            stopEverything();
        }
    }

    private void remove(int notificationId) {
        cards.remove(notificationId);

        if (cards.isEmpty()) {
            stopEverything();
            return;
        }

        // The card holding the foreground slot has gone — the prep-to-delivery handover is exactly
        // this — so the slot moves to whatever is left rather than being left pointing at a
        // notification that no longer exists.
        if (notificationId == foregroundId) {
            foregroundId = 0;
            promote(cards.values().iterator().next());
        }
        schedule();
    }

    private void stopEverything() {
        handler.removeCallbacks(tick);
        cards.clear();
        foregroundId = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE);
        } else {
            stopForegroundLegacy();
        }
        stopSelf();
    }

    @SuppressWarnings("deprecation")
    private void stopForegroundLegacy() {
        stopForeground(true);
    }
}
