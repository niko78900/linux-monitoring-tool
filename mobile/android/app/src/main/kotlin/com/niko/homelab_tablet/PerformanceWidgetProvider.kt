package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PerformanceWidgetProvider : HomeWidgetProvider() {
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

  private fun buildRemoteViews(context: Context, widgetData: SharedPreferences): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.performance_widget)
    val snapshot = WidgetShared.parseSnapshot(widgetData.getString(WIDGET_SNAPSHOT_KEY, null))
    val cpu = snapshot.optNullableDouble("cpu_percent")
    val ram = snapshot.optNullableDouble("memory_percent")
    val gpu = snapshot.optNullableDouble("gpu_utilization_percent")

    views.setOnClickPendingIntent(R.id.widget_container, WidgetShared.launchIntent(context, "overview"))
    views.setOnClickPendingIntent(R.id.widget_gpu_region, WidgetShared.launchIntent(context, "gpu"))
    views.setOnClickPendingIntent(R.id.widget_refresh_button, WidgetShared.refreshIntent(context))
    WidgetShared.setStatus(context, views, snapshot, R.id.widget_status)
    views.setTextViewText(R.id.widget_updated, WidgetShared.relativeUpdateText(snapshot.optNullableLong("last_updated_epoch_ms_utc")))

    views.setTextViewText(R.id.widget_cpu, "CPU ${WidgetShared.percentText(cpu)}  ${WidgetShared.temperatureText(snapshot.optNullableDouble("cpu_temperature_c"))}")
    views.setProgressBar(R.id.widget_cpu_bar, 100, WidgetShared.percentProgress(cpu), false)
    views.setTextViewText(R.id.widget_memory, "RAM ${WidgetShared.percentText(ram)}")
    views.setProgressBar(R.id.widget_memory_bar, 100, WidgetShared.percentProgress(ram), false)
    views.setTextViewText(
        R.id.widget_gpu,
        if (snapshot.optBoolean("gpu_available", false)) {
          "GPU ${WidgetShared.percentText(gpu)}  ${WidgetShared.temperatureText(snapshot.optNullableDouble("gpu_temperature_c"))}"
        } else {
          "GPU N/A"
        },
    )
    views.setProgressBar(R.id.widget_gpu_bar, 100, WidgetShared.percentProgress(gpu), false)
    return views
  }
}
