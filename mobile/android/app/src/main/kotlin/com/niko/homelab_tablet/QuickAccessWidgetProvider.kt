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
      val phoneMode = context.packageName == "com.niko.homelab_monitor"
      views.setTextViewText(R.id.widget_terminal, if (phoneMode) "GPU" else "Terminal")
      views.setTextViewText(R.id.widget_files, if (phoneMode) "History" else "Files")
      views.setTextViewText(R.id.widget_actions, if (phoneMode) "Wake" else "Actions")
      views.setOnClickPendingIntent(R.id.widget_overview, WidgetShared.launchIntent(context, "overview"))
      views.setOnClickPendingIntent(R.id.widget_storage, WidgetShared.launchIntent(context, "storage"))
      views.setOnClickPendingIntent(
          R.id.widget_terminal,
          WidgetShared.launchIntent(context, if (phoneMode) "gpu" else "terminal"),
      )
      views.setOnClickPendingIntent(
          R.id.widget_files,
          WidgetShared.launchIntent(context, if (phoneMode) "history" else "files"),
      )
      views.setOnClickPendingIntent(
          R.id.widget_actions,
          WidgetShared.launchIntent(context, if (phoneMode) "wake" else "actions"),
      )
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
