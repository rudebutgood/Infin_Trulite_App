package com.infin.trulite

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.view.View
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

class IndexWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val indicesJson = widgetData.getString("indices_json", null)
            
            val views = RemoteViews(context.packageName, R.layout.index_widget)
            
            if (indicesJson.isNullOrEmpty()) {
                views.setViewVisibility(R.id.empty_view, View.VISIBLE)
                views.setViewVisibility(R.id.indices_container, View.GONE)
            } else {
                views.setViewVisibility(R.id.empty_view, View.GONE)
                views.setViewVisibility(R.id.indices_container, View.VISIBLE)
                try {
                    val array = JSONArray(indicesJson)
                    val itemIds = intArrayOf(
                        R.id.item1, R.id.item2, R.id.item3, R.id.item4, R.id.item5, R.id.item6,
                        R.id.item7, R.id.item8, R.id.item9, R.id.item10, R.id.item11, R.id.item12
                    )
                    
                    for (i in itemIds.indices) {
                        if (i < array.length()) {
                            val item = array.getJSONObject(i)
                            val itemView = RemoteViews(context.packageName, R.layout.index_item_row)
                            
                            itemView.setTextViewText(R.id.index_name, item.getString("name"))
                            itemView.setTextViewText(R.id.index_value, "₹" + item.getString("last"))
                            itemView.setTextViewText(R.id.index_change, (if (item.getBoolean("isPositive")) "+" else "") + item.getString("change") + "%")
                            itemView.setTextColor(R.id.index_change, if (item.getBoolean("isPositive")) 0xFF4CAF50.toInt() else 0xFFF44336.toInt())
                            
                            // Deep link intent
                            val intent = Intent(context, MainActivity::class.java).apply {
                                action = Intent.ACTION_VIEW
                                data = Uri.parse("infin-trulite://indices?name=${item.getString("name")}")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            val pendingIntent = android.app.PendingIntent.getActivity(
                                context, 
                                i, 
                                intent, 
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                            )
                            itemView.setOnClickPendingIntent(R.id.row_container, pendingIntent)

                            views.removeAllViews(itemIds[i])
                            views.addView(itemIds[i], itemView)
                            views.setViewVisibility(itemIds[i], View.VISIBLE)
                        } else {
                            views.setViewVisibility(itemIds[i], View.GONE)
                        }
                    }
                } catch (e: Exception) {
                    views.setViewVisibility(R.id.empty_view, View.VISIBLE)
                    views.setTextViewText(R.id.empty_view, "Error loading data")
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
