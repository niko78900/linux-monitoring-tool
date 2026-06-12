package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class StorageHealthWidgetProvider : HomeWidgetProvider() {
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
    val views = RemoteViews(context.packageName, R.layout.storage_health_widget)
    val snapshot = WidgetShared.parseSnapshot(widgetData.getString(WIDGET_SNAPSHOT_KEY, null))
    val showSecondary = widgetData.getBoolean(WIDGET_SHOW_SECONDARY_STORAGE_KEY, false)

    views.setOnClickPendingIntent(R.id.widget_container, WidgetShared.launchIntent(context, "storage"))
    views.setOnClickPendingIntent(R.id.widget_refresh_button, WidgetShared.refreshIntent(context))
    WidgetShared.setStatus(context, views, snapshot, R.id.widget_status)
    views.setTextViewText(R.id.widget_updated, WidgetShared.relativeUpdateText(snapshot.optNullableLong("last_updated_epoch_ms_utc")))

    val primaryLabel = snapshot.optNullableString("primary_disk_label") ?: "Primary"
    views.setTextViewText(
        R.id.widget_primary_storage,
        "$primaryLabel ${WidgetShared.percentText(snapshot.optNullableDouble("primary_disk_percent"))}  free ${WidgetShared.bytesText(snapshot.optNullableLong("primary_disk_free_bytes"))}",
    )

    val secondaryLabel = snapshot.optNullableString("secondary_disk_label")
    if (showSecondary && secondaryLabel != null) {
      views.setViewVisibility(R.id.widget_secondary_storage, View.VISIBLE)
      views.setTextViewText(
          R.id.widget_secondary_storage,
          "$secondaryLabel ${WidgetShared.percentText(snapshot.optNullableDouble("secondary_disk_percent"))}  free ${WidgetShared.bytesText(snapshot.optNullableLong("secondary_disk_free_bytes"))}",
      )
    } else {
      views.setViewVisibility(R.id.widget_secondary_storage, View.GONE)
    }
    views.setTextViewText(R.id.widget_health, WidgetShared.healthSummary(snapshot))
    return views
  }
}
