package com.siteonlab.zopiq_rider

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of two things Dart cannot reach.
 *
 * **The battery exemption** (`core/battery_optimisation.dart`, audit RID-001)
 * exists because a foreground service is necessary for live tracking to survive
 * the rider opening Google Maps, and on most of this fleet's handsets it is not
 * sufficient: the OEM battery killer stops it anyway unless the app is on the
 * exemption list.
 *
 * **The alarm volume** (`features/notifications/offer_ring.dart`, 0148) exists
 * because a job offer rings on the alarm stream — the right stream, since silent
 * and vibrate modes do not mute it — but a rider who once turned their alarm
 * down to a third gets a ring at a third. The vendor app has carried exactly
 * this since 0128.
 *
 * Nothing here runs when the app is dead, and the ring does not need it to:
 * when FCM wakes the app from killed, the ring is drawn by a background Dart
 * isolate that has no activity and therefore no method channel, and the Dart
 * side expects the `MissingPluginException` and rings at whatever the alarm
 * level happens to be.
 */
class MainActivity : FlutterActivity() {
    /** The alarm level before we raised it, or null when we have not. */
    private var previousVolume: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isExempt" -> result.success(isExempt())
                    "openSettings" -> result.success(openSettings())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RING_CHANNEL)
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

    /**
     * Borrowed, not taken. [previousVolume] is the level found at boost time and
     * the only thing `restore` will set; a restore that was never preceded by a
     * boost does nothing at all. The one gap is a hard process crash while
     * ringing, which loses the remembered level — worth knowing, not worth
     * persisting to disk over.
     */
    private fun boostAlarmVolume() {
        val manager = audio() ?: return
        // Already boosted: keep the *original* level, not the max we just set.
        if (previousVolume != null) return
        try {
            val max = manager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            previousVolume = manager.getStreamVolume(AudioManager.STREAM_ALARM)
            // No flags: a volume toast on top of a ringing offer is noise about
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
            // Nothing sensible to do; the rider's slider is where it is.
        }
    }

    override fun onDestroy() {
        // Closing the app mid-ring must not leave the alarm pinned at maximum.
        restoreAlarmVolume()
        super.onDestroy()
    }

    /**
     * `isIgnoringBatteryOptimizations` is API 23 and our floor is 24, so there
     * is nothing to version-guard.
     */
    private fun isExempt(): Boolean {
        // A missing PowerManager is reported as exempt: see the Dart doc for why
        // silence beats nagging about a setting we could not read.
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * The list screen, deliberately, and not
     * `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — that one is a single tap
     * but needs a Play-restricted permission this app would not be granted.
     *
     * Some OEM builds ship neither screen, hence the catch. A rider on such a
     * phone is told nothing rather than shown a crash.
     */
    private fun openSettings(): Boolean =
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }

    private companion object {
        const val CHANNEL = "zopiq/rider/battery"
        const val RING_CHANNEL = "zopiqnow/rider_ring"
    }
}
