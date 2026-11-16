package app.asani.patient_app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phone maker, so the Account screen shows the Autostart tip only on Xiaomi/Redmi/POCO.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "asani/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
                else -> result.notImplemented()
            }
        }
    }
}
