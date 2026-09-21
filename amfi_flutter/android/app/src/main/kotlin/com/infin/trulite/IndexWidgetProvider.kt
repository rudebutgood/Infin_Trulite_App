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
import kotlinx.coroutines.*
import java.net.URL
import java.net.HttpURLConnection
import java.util.Locale
import java.text.SimpleDateFormat
import java.util.Date

class IndexWidgetProvider : AppWidgetProvider() {
    companion object {
        const val ACTION_REFRESH = "com.infin.trulite.ACTION_REFRESH"
        const val ACTION_TOGGLE_COLS = "com.infin.trulite.ACTION_TOGGLE_COLS"
        const val ACTION_DO_NOTHING = "com.infin.trulite.ACTION_DO_NOTHING"
        const val ACTION_SHOW_FULL_NAME = "com.infin.trulite.ACTION_SHOW_FULL_NAME"
        const val ACTION_GRID_ITEM_CLICK = "com.infin.trulite.ACTION_GRID_ITEM_CLICK"
        const val EXTRA_INDEX_NAME = "com.infin.trulite.EXTRA_INDEX_NAME"
        const val EXTRA_INDEX_SYMBOL = "com.infin.trulite.EXTRA_INDEX_SYMBOL"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = android.content.ComponentName(context, IndexWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

        when (intent.action) {
            ACTION_DO_NOTHING -> return // Explicitly catch and ignore
            ACTION_REFRESH -> {
                val pendingResult = goAsync()
                // Show progress bar spinner
                for (appWidgetId in appWidgetIds) {
                    val views = RemoteViews(context.packageName, R.layout.index_widget)
                    views.setViewVisibility(R.id.widget_logo, View.GONE)
                    views.setViewVisibility(R.id.refresh_progress, View.VISIBLE)
                    appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
                }
                
                // Fetch data in background
                scope.launch {
                    try {
                        withTimeout(5000) { // Max 5 seconds for refresh
                            performRefresh(context)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        withContext(Dispatchers.Main) {
                            onUpdate(context, appWidgetManager, appWidgetIds)
                            pendingResult.finish()
                        }
                    }
                }
            }
            ACTION_SHOW_FULL_NAME -> {
                val name = intent.getStringExtra(EXTRA_INDEX_NAME)
                if (name != null) {
                    android.widget.Toast.makeText(context, name, android.widget.Toast.LENGTH_SHORT).show()
                }
            }
            ACTION_TOGGLE_COLS -> {
                val widgetData = HomeWidgetPlugin.getData(context)
                val current = widgetData.getInt("user_columns", 0)
                val next = if (current == 0) 1 else if (current == 1) 2 else 0
                widgetData.edit().putInt("user_columns", next).apply()
                onUpdate(context, appWidgetManager, appWidgetIds)
            }
            ACTION_GRID_ITEM_CLICK -> {
                val name = intent.getStringExtra(EXTRA_INDEX_NAME) ?: return
                val symbol = intent.getStringExtra(EXTRA_INDEX_SYMBOL) ?: ""
                
                // Construct URL with symbol, fallback to name if symbol is empty
                val urlSymbol = if (symbol.isNotEmpty()) symbol else name
                
                // Open app with deep link to show NSE Tracker in browser popup
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("infin-trulite://indices?name=${Uri.encode(name)}&symbol=${Uri.encode(urlSymbol)}&open_browser=true")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                try {
                    context.startActivity(openIntent)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun performRefresh(context: Context) {
        try {
            // 1. Get cookies first
            val mainUrl = URL("https://www.nseindia.com/")
            val conn1 = mainUrl.openConnection() as HttpURLConnection
            conn1.connectTimeout = 4000
            conn1.readTimeout = 4000
            conn1.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36")
            conn1.connect()
            val cookies = conn1.headerFields["Set-Cookie"]?.joinToString("; ")
            conn1.disconnect()

            // 2. Fetch indices
            val apiUrl = URL("https://www.nseindia.com/api/allIndices")
            val conn2 = apiUrl.openConnection() as HttpURLConnection
            conn2.connectTimeout = 4000
            conn2.readTimeout = 4000
            conn2.setRequestProperty("User-Agent", "Mozilla/5.0")
            conn2.setRequestProperty("Accept", "application/json")
            if (cookies != null) conn2.setRequestProperty("Cookie", cookies)
            
            val response = conn2.inputStream.bufferedReader().use { it.readText() }
            conn2.disconnect()

            val json = JSONObject(response)
            val dataArray = json.getJSONArray("data")
            
            // 3. Update bookmarked indices in prefs
            val widgetData = HomeWidgetPlugin.getData(context)
            
            // Let's read the existing indices_json and update ONLY the values of indices that are already there.
            val currentJsonStr = widgetData.getString("indices_json", null)
            if (!currentJsonStr.isNullOrEmpty()) {
                val currentArray = JSONArray(currentJsonStr)
                val updatedArray = JSONArray()
                
                // Map of all indices from API
                val apiMap = mutableMapOf<String, JSONObject>()
                for (i in 0 until dataArray.length()) {
                    val item = dataArray.getJSONObject(i)
                    apiMap[item.getString("index").lowercase()] = item
                }
                
                for (i in 0 until currentArray.length()) {
                    val item = currentArray.getJSONObject(i)
                    val name = item.getString("name")
                    val apiItem = apiMap[name.lowercase()]
                    
                    if (apiItem != null) {
                        item.put("last", String.format("%.2f", apiItem.getDouble("last")))
                        item.put("change", String.format("%.2f", apiItem.getDouble("percentChange")))
                        item.put("isPositive", apiItem.getDouble("percentChange") >= 0)
                        // Use indexSymbol for URLs, fallback to index
                        val sym = apiItem.optString("indexSymbol", apiItem.optString("index", ""))
                        item.put("symbol", sym)
                        // Removed fetching chartPath SVG to avoid polling/pulling it from the API
                        item.put("chartPath", "")
                    }
                    updatedArray.put(item)
                }
                widgetData.edit().putString("indices_json", updatedArray.toString()).apply()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)

        for (appWidgetId in appWidgetIds) {
            val indicesJson = widgetData.getString("indices_json", null)
            
            // Determine columns count
            val widgetCols = widgetData.getInt("user_columns_$appWidgetId", widgetData.getInt("user_columns", 0))
            var columns = 2
            if (widgetCols != 0) {
                columns = widgetCols
            } else {
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                columns = if (minWidth != 0 && minWidth < 250) 1 else 2
            }

            // Always use the same single root layout resource file to completely bypass layout re-inflation bugs
            val views = RemoteViews(context.packageName, R.layout.index_widget)

            // 1. DUMMY INTENT TO STOP BACKGROUND CLICKS
            val nothingIntent = Intent(context, IndexWidgetProvider::class.java).apply {
                action = ACTION_DO_NOTHING
                data = Uri.parse("nothing://$appWidgetId")
            }
            val nothingPendingIntent = android.app.PendingIntent.getBroadcast(
                context, appWidgetId + 2000, nothingIntent, 
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.header_bar, nothingPendingIntent)
            
            // Hide progress bar and show logo
            views.setViewVisibility(R.id.widget_logo, View.VISIBLE)
            views.setViewVisibility(R.id.refresh_progress, View.GONE)

            // Update last refresh time
            val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
            views.setTextViewText(R.id.last_refresh, sdf.format(Date()))

            // Manual refresh on LOGO CONTAINER
            val refreshIntent = Intent(context, IndexWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            val refreshPendingIntent = android.app.PendingIntent.getBroadcast(
                context, 0, refreshIntent, 
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.logo_refresh_btn, refreshPendingIntent)

            // Determine active target grid ID based on columns selection, and hide inactive grids
            val activeGridId = when (columns) {
                1 -> R.id.indices_grid_1col
                3 -> R.id.indices_grid_3col
                else -> R.id.indices_grid_2col
            }

            val allGridIds = intArrayOf(R.id.indices_grid_1col, R.id.indices_grid_2col, R.id.indices_grid_3col)
            for (gridId in allGridIds) {
                if (gridId == activeGridId && !indicesJson.isNullOrEmpty()) {
                    views.setViewVisibility(gridId, View.VISIBLE)
                } else {
                    views.setViewVisibility(gridId, View.GONE)
                }
            }

            // Set up GridView adapter specifically on the active target grid view instance
            val serviceIntent = Intent(context, IndexWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("columns", columns)
                data = Uri.parse("custom://widget/id/$appWidgetId/cols/$columns")
            }
            views.setRemoteAdapter(activeGridId, serviceIntent)
            views.setEmptyView(activeGridId, R.id.empty_view)

            // Set up multi-purpose PendingIntent template
            val templateIntent = Intent(context, IndexWidgetProvider::class.java).apply {
                action = ACTION_GRID_ITEM_CLICK
            }
            val templatePendingIntent = android.app.PendingIntent.getBroadcast(
                context, appWidgetId + 5000, templateIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_MUTABLE
            )
            views.setPendingIntentTemplate(activeGridId, templatePendingIntent)

            if (indicesJson.isNullOrEmpty()) {
                views.setViewVisibility(R.id.empty_view, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.empty_view, View.GONE)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, activeGridId)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }
}
