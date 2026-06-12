package com.niko.homelab_tablet

import android.app.PendingIntent
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.roundToInt

const val WIDGET_SNAPSHOT_KEY = "server_widget_snapshot"
const val WIDGET_SHOW_NETWORK_ROW_KEY = "server_widget_show_network_row"
const val WIDGET_SHOW_SECONDARY_STORAGE_KEY = "server_widget_show_secondary_storage"

object WidgetShared {
  fun parseSnapshot(raw: String?): JSONObject {
    return try {
      if (raw.isNullOrBlank()) JSONObject() else JSONObject(raw)
    } catch (_: Exception) {
      JSONObject()
    }
  }

  fun launchIntent(context: Context, target: String): PendingIntent {
    return HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("homelabtablet://$target"),
    )
  }

  fun refreshIntent(context: Context): PendingIntent {
    return HomeWidgetBackgroundIntent.getBroadcast(
        context,
        Uri.parse("homelabtablet://refresh"),
    )
  }

  fun setStatus(
      context: Context,
      views: RemoteViews,
      snapshot: JSONObject,
      statusViewId: Int,
  ) {
    views.setTextViewText(statusViewId, statusLabel(snapshot))
    views.setTextColor(statusViewId, ContextCompat.getColor(context, statusColor(snapshot)))
  }

  fun statusLabel(snapshot: JSONObject): String {
    val reachable = snapshot.optBoolean("server_reachable", false)
    val stale = snapshot.optBoolean("is_stale", true)
    return when {
      !reachable -> "OFFLINE"
      stale -> "STALE"
      else -> "ONLINE"
    }
  }

  fun statusColor(snapshot: JSONObject): Int {
    val reachable = snapshot.optBoolean("server_reachable", false)
    val stale = snapshot.optBoolean("is_stale", true)
    return when {
      !reachable -> R.color.widget_status_offline
      stale -> R.color.widget_status_stale
      else -> R.color.widget_status_online
    }
  }

  fun percentText(value: Double?): String {
    return value?.let { "${it.roundToInt()}%" } ?: "N/A"
  }

  fun percentProgress(value: Double?): Int {
    return value?.roundToInt()?.coerceIn(0, 100) ?: 0
  }

  fun temperatureText(value: Double?): String {
    return value?.let { "${it.roundToInt()}C" } ?: "N/A"
  }

  fun rateText(value: Double?): String {
    if (value == null) {
      return "N/A"
    }
    val absValue = abs(value)
    return when {
      absValue >= 1024 * 1024 * 1024 -> String.format("%.1f GB/s", value / (1024 * 1024 * 1024))
      absValue >= 1024 * 1024 -> String.format("%.1f MB/s", value / (1024 * 1024))
      absValue >= 1024 -> String.format("%.0f KB/s", value / 1024)
      else -> "${value.roundToInt()} B/s"
    }
  }

  fun bytesText(value: Long?): String {
    if (value == null) {
      return "N/A"
    }
    val absValue = abs(value.toDouble())
    return when {
      absValue >= 1024 * 1024 * 1024 * 1024 -> String.format("%.1f TB", value / 1099511627776.0)
      absValue >= 1024 * 1024 * 1024 -> String.format("%.1f GB", value / 1073741824.0)
      absValue >= 1024 * 1024 -> String.format("%.0f MB", value / 1048576.0)
      absValue >= 1024 -> String.format("%.0f KB", value / 1024.0)
      else -> "$value B"
    }
  }

  fun linkSpeedText(value: Long?): String {
    if (value == null || value <= 0) {
      return "Link N/A"
    }
    return if (value >= 1000) {
      "Link ${String.format("%.1f", value / 1000.0).trimEnd('0').trimEnd('.')} Gbps"
    } else {
      "Link $value Mbps"
    }
  }

  fun relativeUpdateText(epochMs: Long?): String {
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

  fun healthSummary(snapshot: JSONObject): String {
    val raid = snapshot.optNullableString("raid_health")
    val disk = snapshot.optNullableString("disk_health")
    return when {
      raid != null -> "RAID ${raid.uppercase()}"
      disk != null -> "Disk ${disk.uppercase()}"
      else -> "Health N/A"
    }
  }
}

fun JSONObject.optNullableDouble(key: String): Double? {
  if (!has(key) || isNull(key)) {
    return null
  }
  return optDouble(key)
}

fun JSONObject.optNullableLong(key: String): Long? {
  if (!has(key) || isNull(key)) {
    return null
  }
  return optLong(key)
}

fun JSONObject.optNullableString(key: String): String? {
  val value = optString(key, "").trim()
  return value.ifEmpty { null }
}
