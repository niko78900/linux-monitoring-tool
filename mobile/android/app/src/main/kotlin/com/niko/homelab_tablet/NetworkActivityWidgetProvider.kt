package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class NetworkActivityWidgetProvider : HomeWidgetProvider() {
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
    val views = RemoteViews(context.packageName, R.layout.network_activity_widget)
    val snapshot = WidgetShared.parseSnapshot(widgetData.getString(WIDGET_SNAPSHOT_KEY, null))

    views.setOnClickPendingIntent(R.id.widget_container, WidgetShared.launchIntent(context, "network"))
    views.setOnClickPendingIntent(R.id.widget_refresh_button, WidgetShared.refreshIntent(context))
    WidgetShared.setStatus(context, views, snapshot, R.id.widget_status)
    views.setTextViewText(R.id.widget_updated, WidgetShared.relativeUpdateText(snapshot.optNullableLong("last_updated_epoch_ms_utc")))
    views.setTextViewText(R.id.widget_receive, "RX ${WidgetShared.rateText(snapshot.optNullableDouble("network_recv_bytes_per_second"))}")
    views.setTextViewText(R.id.widget_transmit, "TX ${WidgetShared.rateText(snapshot.optNullableDouble("network_send_bytes_per_second"))}")
    views.setTextViewText(R.id.widget_receive_total, "Total RX ${WidgetShared.bytesText(snapshot.optNullableLong("network_bytes_recv_total"))}")
    views.setTextViewText(R.id.widget_transmit_total, "Total TX ${WidgetShared.bytesText(snapshot.optNullableLong("network_bytes_sent_total"))}")
    views.setTextViewText(R.id.widget_link_speed, WidgetShared.linkSpeedText(snapshot.optNullableLong("top_network_speed_mbps")))
    return views
  }
}
