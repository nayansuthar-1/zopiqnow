package com.siteonlab.zopiq_rider

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of `core/battery_optimisation.dart` (audit RID-001).
 *
 * Two calls, both of which exist because a foreground service is necessary for
 * live tracking to survive the rider opening Google Maps, and on most of this
 * fleet's handsets it is not sufficient: the OEM battery killer stops it anyway
 * unless the app is on the exemption list.
 *
 * Nothing here runs when the app is dead, and nothing here needs to — this is a
 * MethodChannel on the live engine, not a background entry point.
 */
class MainActivity : FlutterActivity() {
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
    }
}
