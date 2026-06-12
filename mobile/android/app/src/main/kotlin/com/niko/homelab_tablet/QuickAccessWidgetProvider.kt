package com.niko.homelab_tablet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class QuickAccessWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.quick_access_widget)
      views.setOnClickPendingIntent(R.id.widget_overview, WidgetShared.launchIntent(context, "overview"))
      views.setOnClickPendingIntent(R.id.widget_storage, WidgetShared.launchIntent(context, "storage"))
      views.setOnClickPendingIntent(R.id.widget_terminal, WidgetShared.launchIntent(context, "terminal"))
      views.setOnClickPendingIntent(R.id.widget_files, WidgetShared.launchIntent(context, "files"))
      views.setOnClickPendingIntent(R.id.widget_actions, WidgetShared.launchIntent(context, "actions"))
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
