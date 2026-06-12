package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

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
    val snapshot = WidgetShared.parseSnapshot(widgetData.getString(WIDGET_SNAPSHOT_KEY, null))
    val showNetworkRow = widgetData.getBoolean(WIDGET_SHOW_NETWORK_ROW_KEY, false)

    views.setOnClickPendingIntent(R.id.widget_container, WidgetShared.launchIntent(context, "overview"))
    views.setOnClickPendingIntent(R.id.widget_storage, WidgetShared.launchIntent(context, "storage"))
    views.setOnClickPendingIntent(R.id.widget_refresh_button, WidgetShared.refreshIntent(context))

    views.setTextViewText(
        R.id.widget_hostname,
        snapshot.optString("hostname", "Homelab Server"),
    )
    WidgetShared.setStatus(context, views, snapshot, R.id.widget_status)
    views.setTextViewText(
        R.id.widget_updated,
        WidgetShared.relativeUpdateText(snapshot.optNullableLong("last_updated_epoch_ms_utc")),
    )
    views.setTextViewText(
        R.id.widget_cpu,
        "CPU ${WidgetShared.percentText(snapshot.optNullableDouble("cpu_percent"))} ${WidgetShared.temperatureText(snapshot.optNullableDouble("cpu_temperature_c"))}",
    )
    views.setTextViewText(
        R.id.widget_memory,
        "RAM ${WidgetShared.percentText(snapshot.optNullableDouble("memory_percent"))}",
    )
    views.setTextViewText(
        R.id.widget_gpu,
        if (snapshot.optBoolean("gpu_available", false)) {
          "GPU ${WidgetShared.percentText(snapshot.optNullableDouble("gpu_utilization_percent"))} ${WidgetShared.temperatureText(snapshot.optNullableDouble("gpu_temperature_c"))}"
        } else {
          "GPU N/A"
        },
    )
    views.setTextViewText(R.id.widget_health, WidgetShared.healthSummary(snapshot))

    val diskLabel = snapshot.optNullableString("primary_disk_label") ?: "Storage"
    views.setTextViewText(
        R.id.widget_storage,
        "$diskLabel ${WidgetShared.percentText(snapshot.optNullableDouble("primary_disk_percent"))}",
    )

    if (showNetworkRow) {
      views.setViewVisibility(R.id.widget_network_row, View.VISIBLE)
      views.setTextViewText(
          R.id.widget_network,
          "DOWN ${WidgetShared.rateText(snapshot.optNullableDouble("network_recv_bytes_per_second"))}  UP ${WidgetShared.rateText(snapshot.optNullableDouble("network_send_bytes_per_second"))}",
      )
    } else {
      views.setViewVisibility(R.id.widget_network_row, View.GONE)
    }

    return views
  }
}
