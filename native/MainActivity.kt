package tech.isaacarinola.belloxdydx

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity is REQUIRED by local_auth (fingerprint/face).
// FLAG_SECURE makes the whole app invisible to screenshots and screen
// recorders: captures come out black at the OS level, app-wide.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
