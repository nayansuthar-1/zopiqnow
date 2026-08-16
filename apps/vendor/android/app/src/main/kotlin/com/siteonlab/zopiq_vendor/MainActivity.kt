package com.siteonlab.zopiq_vendor

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter app, and lends it the one thing Dart cannot reach: the
 * device's alarm volume.
 *
 * A new order rings on the alarm stream (see `OrderRing`), which is the right
 * stream — silent and vibrate modes do not mute it. But a vendor who once
 * turned their alarm down to a third gets a ring at a third, and "full audio"
 * was the requirement. So the ring borrows the slider: max while ringing, and
 * exactly whatever it was before once the order is answered.
 *
 * **Borrowed, not taken.** [previousVolume] is the level found at boost time and
 * the only thing `restore` will set; a restore that was never preceded by a
 * boost does nothing at all. `onDestroy` restores too, so closing the app
 * mid-ring does not leave the alarm pinned. The one gap is a hard process
 * crash while ringing, which loses the remembered level — the next boost then
 * reads max as the previous value and the vendor keeps a loud alarm until they
 * change it themselves. Worth knowing; not worth persisting to disk over.
 *
 * ⚠️ Reachable **only while this activity exists**. When FCM wakes the app from
 * killed, the ring is drawn by a background Dart isolate that has no activity
 * and therefore no method channel — the Dart side expects the
 * `MissingPluginException` and rings at the device's own alarm level instead.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "zopiqnow/vendor_ring"
    }

    /** The alarm level before we raised it, or null when we have not. */
    private var previousVolume: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "boost" -> {
                        boostAlarmVolume()
                        result.success(null)
                    }
                    "restore" -> {
                        restoreAlarmVolume()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun audio(): AudioManager? =
        getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private fun boostAlarmVolume() {
        val manager = audio() ?: return
        // Already boosted: keep the *original* level, not the max we just set.
        if (previousVolume != null) return
        try {
            val max = manager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            previousVolume = manager.getStreamVolume(AudioManager.STREAM_ALARM)
            // No flags: a volume toast on top of a ringing order is noise about
            // noise, and FLAG_PLAY_SOUND would beep over the ringtone.
            manager.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
        } catch (e: SecurityException) {
            // Some OEM builds refuse a volume change while a Do Not Disturb
            // policy is active. The ring still plays; it just plays quieter.
            previousVolume = null
        }
    }

    private fun restoreAlarmVolume() {
        val manager = audio() ?: return
        val previous = previousVolume ?: return
        previousVolume = null
        try {
            manager.setStreamVolume(AudioManager.STREAM_ALARM, previous, 0)
        } catch (e: SecurityException) {
            // Nothing sensible to do; the vendor's slider is where it is.
        }
    }

    override fun onDestroy() {
        // Closing the app mid-ring must not leave the alarm pinned at maximum.
        restoreAlarmVolume()
        super.onDestroy()
    }
}
