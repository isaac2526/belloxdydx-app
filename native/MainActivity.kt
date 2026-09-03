package tech.isaacarinola.belloxdydx

import android.content.Context
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is REQUIRED by local_auth (fingerprint/face).
class MainActivity : FlutterFragmentActivity() {

    companion object {
        // Our own preferences file, written from Dart over a method
        // channel. Deliberately not Flutter's shared_preferences store:
        // that one encodes values in a private format which is not a
        // contract, and this has to be readable from Kotlin before a
        // single line of Dart has run.
        const val PREFS = "bx_native"
        const val KEY_LAUNCH_THEME = "launch_theme"
        const val KEY_ALLOW_SCREENSHOTS = "allow_screenshots"
        const val CHANNEL = "belloxdydx/native"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // The window background the SYSTEM paints comes from the theme
        // in the manifest and is chosen before any of our code runs, so
        // it cannot follow a stored preference — it is always light,
        // which is what a first install must show. Repainting it here
        // covers the rest of the wait for a student who chose dark.
        if (prefs.getString(KEY_LAUNCH_THEME, "light") == "dark") {
            window.setBackgroundDrawable(
                ColorDrawable(ContextCompat.getColor(this, R.color.bx_ground_dark)),
            )
        }

        super.onCreate(savedInstanceState)
        applyScreenshotPolicy(prefs.getBoolean(KEY_ALLOW_SCREENSHOTS, false))
    }

    // FLAG_SECURE makes the app invisible to screenshots and screen
    // recorders: captures come out black at the OS level, app-wide. It
    // can be added and cleared at any time, so a setting fetched from
    // the backend after launch still takes effect on this same screen.
    private fun applyScreenshotPolicy(allow: Boolean) {
        if (allow) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                when (call.method) {
                    // Remembered for the NEXT launch, so the window the
                    // student sees before Flutter starts already matches
                    // the theme they chose.
                    "setLaunchTheme" -> {
                        val mode = call.arguments as? String ?: "light"
                        prefs.edit().putString(KEY_LAUNCH_THEME, mode).apply()
                        result.success(true)
                    }

                    "setAllowScreenshots" -> {
                        val allow = call.arguments as? Boolean ?: false
                        prefs.edit().putBoolean(KEY_ALLOW_SCREENSHOTS, allow).apply()
                        runOnUiThread { applyScreenshotPolicy(allow) }
                        result.success(true)
                    }

                    "screenshotPolicy" -> result.success(
                        mapOf(
                            "enforceable" to true,
                            "allowed" to prefs.getBoolean(KEY_ALLOW_SCREENSHOTS, false),
                            "mechanism" to "FLAG_SECURE",
                        ),
                    )

                    else -> result.notImplemented()
                }
            }
    }
}
