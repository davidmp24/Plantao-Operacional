package com.davidmp.plantao

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.app.PendingIntent
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Widget do Plantão Operacional para tela inicial do Android.
 * Exibe o status do dia atual (compromisso/folga) usando dados
 * salvos pelo Flutter via home_widget package.
 */
class PlantaoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)

            // Lê dados salvos pelo Flutter
            val statusTitle = widgetData.getString("widget_status_title", "Nenhum compromisso")
            val statusColor = widgetData.getString("widget_status_color", "#10A37F")
            val nextItem = widgetData.getString("widget_next_item", "")
            val dateStr = SimpleDateFormat("EEEE, d 'de' MMMM", Locale("pt", "BR")).format(Date())

            val views = RemoteViews(context.packageName, R.layout.plantao_widget_layout)

            // Atualiza views
            views.setTextViewText(R.id.widget_date, dateStr.replaceFirstChar { it.uppercase() })
            views.setTextViewText(R.id.widget_status, statusTitle ?: "Nenhum compromisso")
            views.setTextViewText(R.id.widget_next, nextItem ?: "")

            // Toque abre o app
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_date, pendingIntent)
                views.setOnClickPendingIntent(R.id.widget_status, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
