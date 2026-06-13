package com.niko.homelab_tablet

import android.content.Intent
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
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
      when (call.method) {
        "openUrgentAlertChannelSettings" -> {
          openUrgentAlertChannelSettings()
          result.success(null)
        }
        "notificationReadiness" -> {
          result.success(notificationReadiness())
        }
        else -> result.notImplemented()
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

  private fun notificationReadiness(): Map<String, Any?> {
    val notificationsEnabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return mapOf(
          "notificationsEnabled" to notificationsEnabled,
          "channelExists" to true,
          "channelImportance" to if (notificationsEnabled) 4 else 0,
          "channelSoundEnabled" to notificationsEnabled,
          "channelVibrationEnabled" to notificationsEnabled,
      )
    }

    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val channel = manager.getNotificationChannel("homelab_urgent_alerts_v1")
    return mapOf(
        "notificationsEnabled" to notificationsEnabled,
        "channelExists" to (channel != null),
        "channelImportance" to (channel?.importance ?: 0),
        "channelSoundEnabled" to (channel?.sound != null),
        "channelVibrationEnabled" to (channel?.shouldVibrate() ?: false),
    )
  }
}
