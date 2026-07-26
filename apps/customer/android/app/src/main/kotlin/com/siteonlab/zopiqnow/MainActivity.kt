package com.siteonlab.zopiqnow

import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity

/**
 * Ask the display for its highest refresh rate.
 *
 * A 90/120 Hz Android phone whose system default mode is 60 Hz renders a Flutter app at 60 unless
 * the window asks for something better. Nothing else in this app asks, so the whole feed has been
 * running at half the frame rate the panel can draw.
 *
 * `preferredDisplayModeId` is API 23+, so this reaches the Android 10 floor and below it, with no
 * new dependency — the `flutter_displaymode` package does the same thing and would collide with the
 * version freeze for no gain.
 *
 * `Surface.setFrameRate()` (API 30+) is deliberately *not* used alongside it: it needs the surface
 * Flutter renders into, which `FlutterActivity` does not expose, and reaching into `FlutterView`'s
 * internals to find it would be a fragile way to say the same thing the mode request already says.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    private fun requestHighestRefreshRate() {
        val display = activeDisplay ?: return
        val current = display.mode ?: return

        // Filter to the current resolution first. Naively taking the highest-refresh mode on the
        // panel can also switch resolution — a 120 Hz mode is often offered only at 1080p on a
        // 1440p phone — and trading sharpness for smoothness is not what this change is for.
        val best = display.supportedModes
            ?.filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            ?.maxByOrNull { it.refreshRate }
            ?: return

        // Float comparison with a margin: a 60 Hz panel reports 59.94, and re-requesting the mode
        // the window is already in makes the compositor renegotiate for nothing.
        if (best.refreshRate <= current.refreshRate + 1f) return

        window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
    }

    /**
     * `Activity.getDisplay()` arrived in API 30; below that the deprecated
     * `WindowManager.getDefaultDisplay()` is the only route, and it is the correct one there.
     */
    private val activeDisplay: Display?
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager?.defaultDisplay
        }
}
