package tech.isaacarinola.belloxdydx

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

// FLAG_SECURE: the whole app becomes invisible to screenshots,
// screen recorders and the recent-apps preview. Captures come out
// BLACK. This is the native power no website can have.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
