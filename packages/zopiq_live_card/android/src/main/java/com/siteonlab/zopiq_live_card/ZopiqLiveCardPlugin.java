package com.siteonlab.zopiq_live_card;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.text.TextUtils;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * The bridge. Two jobs and nothing else: draw the card when Dart says the order moved, and tell Dart
 * which order a tap on the card was asking about.
 *
 * <p><b>Why this runs twice.</b> Two Flutter engines in this process register this plugin — the
 * app's own, and the one {@code firebase_messaging} spins up to run the background message handler
 * with the app killed. Both get their own instance and their own channel; only the app's is ever
 * attached to an activity. That is exactly the split the card needs: the background instance draws,
 * the foreground instance also listens for taps.
 */
public final class ZopiqLiveCardPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
                PluginRegistry.NewIntentListener {

    private static final String CHANNEL = "com.siteonlab.zopiq_live_card";

    private MethodChannel channel;
    private Context context;
    private Activity activity;

    /**
     * A tap that arrived before Dart was ready to hear about it.
     *
     * <p>A cold start from the lock screen runs the whole app between the tap and the first time
     * anything asks where it should navigate, so the order id waits here until {@code
     * consumeLaunchOrderId} collects it. Static because the activity's plugin instance is torn down
     * and rebuilt across a configuration change, and a rotation on the way in is not a reason to
     * lose the tap.
     */
    private static String pendingLaunchOrderId;

    // ---------------------------------------------------------------- FlutterPlugin

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }

    // ---------------------------------------------------------------- calls from Dart

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (context == null) {
            result.error("no_context", "The plugin is not attached to an engine.", null);
            return;
        }

        switch (call.method) {
            case "show":
                LiveCardNotification.show(
                        context,
                        intArg(call, "id"),
                        stringArg(call, "orderId"),
                        stringArg(call, "title"),
                        stringArg(call, "body"),
                        stringArg(call, "subText"),
                        intArg(call, "progress"));
                result.success(null);
                break;

            case "cancel":
                LiveCardNotification.cancel(context, intArg(call, "id"));
                result.success(null);
                break;

            case "consumeLaunchOrderId":
                // Drain the activity's intent first: on a cold start the plugin can be attached to
                // the engine before it is attached to the activity, so the latch below may still be
                // empty when Dart asks.
                takeOrderIdFrom(activity == null ? null : activity.getIntent());
                final String pending = pendingLaunchOrderId;
                pendingLaunchOrderId = null;
                result.success(pending);
                break;

            default:
                result.notImplemented();
        }
    }

    // ---------------------------------------------------------------- taps

    @Override
    public boolean onNewIntent(Intent intent) {
        // The app was already running. There is a live channel, so hand it straight over rather
        // than parking it and waiting to be asked.
        final String orderId = readOrderId(intent);
        if (orderId != null && channel != null) {
            channel.invokeMethod("onOrderTapped", orderId);
        }
        // Never consume the intent: app_links and firebase_messaging read the same one.
        return false;
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
        binding.addOnNewIntentListener(this);
        takeOrderIdFrom(activity.getIntent());
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    private static void takeOrderIdFrom(Intent intent) {
        final String orderId = readOrderId(intent);
        if (orderId != null) pendingLaunchOrderId = orderId;
    }

    /**
     * Read the order id out of an intent and strike it off, so a resume or a rotation does not
     * re-navigate someone who has since walked elsewhere in the app.
     */
    private static String readOrderId(Intent intent) {
        if (intent == null) return null;
        final String orderId = intent.getStringExtra(LiveCardNotification.EXTRA_ORDER_ID);
        if (TextUtils.isEmpty(orderId)) return null;
        intent.removeExtra(LiveCardNotification.EXTRA_ORDER_ID);
        return orderId;
    }

    // ---------------------------------------------------------------- argument plumbing

    private static String stringArg(MethodCall call, String name) {
        return call.argument(name);
    }

    private static int intArg(MethodCall call, String name) {
        final Integer value = call.argument(name);
        return value == null ? 0 : value;
    }
}
