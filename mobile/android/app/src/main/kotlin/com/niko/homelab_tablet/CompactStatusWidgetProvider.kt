package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetProvider

class CompactStatusWidgetProvider : HomeWidgetProvider() {
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
    val views = RemoteViews(context.packageName, R.layout.compact_status_widget)
    val snapshot = WidgetShared.parseSnapshot(widgetData.getString(WIDGET_SNAPSHOT_KEY, null))

    views.setOnClickPendingIntent(R.id.widget_container, WidgetShared.launchIntent(context, "overview"))
    views.setOnClickPendingIntent(R.id.widget_refresh_button, WidgetShared.refreshIntent(context))
    views.setTextViewText(R.id.widget_status, WidgetShared.statusLabel(snapshot))
    views.setTextColor(R.id.widget_status_dot, ContextCompat.getColor(context, WidgetShared.statusColor(snapshot)))
    views.setTextViewText(R.id.widget_cpu, "CPU ${WidgetShared.percentText(snapshot.optNullableDouble("cpu_percent"))}")
    views.setTextViewText(R.id.widget_memory, "RAM ${WidgetShared.percentText(snapshot.optNullableDouble("memory_percent"))}")
    views.setTextViewText(R.id.widget_storage, "Disk ${WidgetShared.percentText(snapshot.optNullableDouble("primary_disk_percent"))}")
    views.setTextViewText(R.id.widget_updated, WidgetShared.relativeUpdateText(snapshot.optNullableLong("last_updated_epoch_ms_utc")))
    return views
  }
}
