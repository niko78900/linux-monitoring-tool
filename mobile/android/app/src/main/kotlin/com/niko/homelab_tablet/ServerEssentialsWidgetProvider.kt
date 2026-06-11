package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.roundToInt

class ServerEssentialsWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      appWidgetManager.updateAppWidget(widgetId, buildRemoteViews(context, widgetData))
    }
  }

  private fun buildRemoteViews(
      context: Context,
      widgetData: SharedPreferences,
  ): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.server_essentials_widget)
    val snapshot = parseSnapshot(widgetData.getString(SNAPSHOT_KEY, null))
    val showNetworkRow = widgetData.getBoolean(SHOW_NETWORK_ROW_KEY, false)

    val launchOverviewIntent =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("homelabtablet://overview"),
        )
    val launchStorageIntent =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("homelabtablet://storage"),
        )
    val refreshIntent =
        HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("homelabtablet://refresh"),
        )

    views.setOnClickPendingIntent(R.id.widget_container, launchOverviewIntent)
    views.setOnClickPendingIntent(R.id.widget_storage, launchStorageIntent)
    views.setOnClickPendingIntent(R.id.widget_refresh_button, refreshIntent)

    views.setTextViewText(
        R.id.widget_hostname,
        snapshot.optString("hostname", "Homelab Server"),
    )

    val reachable = snapshot.optBoolean("server_reachable", false)
    val stale = snapshot.optBoolean("is_stale", true)
    val statusText =
        when {
          !reachable -> "OFFLINE"
          stale -> "STALE"
          else -> "ONLINE"
        }
    views.setTextViewText(R.id.widget_status, statusText)
    views.setTextColor(
        R.id.widget_status,
        ContextCompat.getColor(
            context,
            when {
              !reachable -> R.color.widget_status_offline
              stale -> R.color.widget_status_stale
              else -> R.color.widget_status_online
            },
        ),
    )

    views.setTextViewText(
        R.id.widget_updated,
        formatRelativeUpdate(snapshot.optNullableLong("last_updated_epoch_ms_utc")),
    )
    views.setTextViewText(
        R.id.widget_cpu,
        "CPU ${formatPercent(snapshot.optNullableDouble("cpu_percent"))} ${formatTemperature(snapshot.optNullableDouble("cpu_temperature_c"))}",
    )
    views.setTextViewText(
        R.id.widget_memory,
        "RAM ${formatPercent(snapshot.optNullableDouble("memory_percent"))}",
    )
    views.setTextViewText(
        R.id.widget_gpu,
        if (snapshot.optBoolean("gpu_available", false)) {
          "GPU ${formatPercent(snapshot.optNullableDouble("gpu_utilization_percent"))} ${formatTemperature(snapshot.optNullableDouble("gpu_temperature_c"))}"
        } else {
          "GPU N/A"
        },
    )

    val healthLabel =
        when {
          snapshot.optNullableString("raid_health") != null ->
              "RAID ${snapshot.optNullableString("raid_health")!!.uppercase()}"
          snapshot.optNullableString("disk_health") != null ->
              "Disk ${snapshot.optNullableString("disk_health")!!.uppercase()}"
          else -> "Health N/A"
        }
    views.setTextViewText(R.id.widget_health, healthLabel)

    val diskLabel = snapshot.optNullableString("primary_disk_label") ?: "Storage"
    views.setTextViewText(
        R.id.widget_storage,
        "$diskLabel ${formatPercent(snapshot.optNullableDouble("primary_disk_percent"))}",
    )

    if (showNetworkRow) {
      views.setViewVisibility(R.id.widget_network_row, View.VISIBLE)
      views.setTextViewText(
          R.id.widget_network,
          "DOWN ${formatRate(snapshot.optNullableDouble("network_recv_bytes_per_second"))}  UP ${formatRate(snapshot.optNullableDouble("network_send_bytes_per_second"))}",
      )
    } else {
      views.setViewVisibility(R.id.widget_network_row, View.GONE)
    }

    return views
  }

  private fun parseSnapshot(raw: String?): JSONObject {
    return if (raw.isNullOrBlank()) JSONObject() else JSONObject(raw)
  }

  private fun formatPercent(value: Double?): String {
    return value?.let { "${it.roundToInt()}%" } ?: "N/A"
  }

  private fun formatTemperature(value: Double?): String {
    return value?.let { "${it.roundToInt()}C" } ?: "N/A"
  }

  private fun formatRate(value: Double?): String {
    if (value == null) {
      return "N/A"
    }
    val absValue = abs(value)
    return when {
      absValue >= 1024 * 1024 -> String.format("%.1f MB/s", value / (1024 * 1024))
      absValue >= 1024 -> String.format("%.0f KB/s", value / 1024)
      else -> "${value.roundToInt()} B/s"
    }
  }

  private fun formatRelativeUpdate(epochMs: Long?): String {
    if (epochMs == null || epochMs <= 0) {
      return "updated N/A"
    }
    val elapsedSeconds = ((System.currentTimeMillis() - epochMs) / 1000).coerceAtLeast(0)
    val relative =
        when {
          elapsedSeconds < 60 -> "${elapsedSeconds}s"
          elapsedSeconds < 3600 -> "${elapsedSeconds / 60}m"
          elapsedSeconds < 86400 -> "${elapsedSeconds / 3600}h"
          else -> "${elapsedSeconds / 86400}d"
        }
    return "updated $relative"
  }

  companion object {
    private const val SNAPSHOT_KEY = "server_widget_snapshot"
    private const val SHOW_NETWORK_ROW_KEY = "server_widget_show_network_row"
  }
}

private fun JSONObject.optNullableDouble(key: String): Double? {
  if (!has(key) || isNull(key)) {
    return null
  }
  return optDouble(key)
}

private fun JSONObject.optNullableLong(key: String): Long? {
  if (!has(key) || isNull(key)) {
    return null
  }
  return optLong(key)
}

private fun JSONObject.optNullableString(key: String): String? {
  val value = optString(key, "").trim()
  return value.ifEmpty { null }
}
