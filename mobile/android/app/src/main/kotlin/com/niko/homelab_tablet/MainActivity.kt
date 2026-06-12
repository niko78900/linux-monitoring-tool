package com.niko.homelab_tablet

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.niko.homelab_tablet/notifications",
    ).setMethodCallHandler { call, result ->
      if (call.method == "openUrgentAlertChannelSettings") {
        openUrgentAlertChannelSettings()
        result.success(null)
      } else {
        result.notImplemented()
      }
    }
  }

  private fun openUrgentAlertChannelSettings() {
    val intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            putExtra(Settings.EXTRA_CHANNEL_ID, "homelab_urgent_alerts_v1")
          }
        } else {
          Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = android.net.Uri.parse("package:$packageName")
          }
        }
    startActivity(intent)
  }
}
