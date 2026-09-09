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
                        }
                    }
                }
            }
            ACTION_TOGGLE_COLS -> {
                val widgetData = HomeWidgetPlugin.getData(context)
                val current = widgetData.getInt("user_columns", 0)
                val next = if (current == 0) 1 else if (current == 1) 2 else 0
                widgetData.edit().putInt("user_columns", next).apply()
                onUpdate(context, appWidgetManager, appWidgetIds)
            }
        }
    }

    private fun performRefresh(context: Context) {
        try {
            // 1. Get cookies first
            val mainUrl = URL("https://www.nseindia.com/")
            val conn1 = mainUrl.openConnection() as HttpURLConnection
            conn1.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36")
            conn1.connect()
            val cookies = conn1.headerFields["Set-Cookie"]?.joinToString("; ")
            conn1.disconnect()

            // 2. Fetch indices
            val apiUrl = URL("https://www.nseindia.com/api/allIndices")
            val conn2 = apiUrl.openConnection() as HttpURLConnection
            conn2.setRequestProperty("User-Agent", "Mozilla/5.0")
            conn2.setRequestProperty("Accept", "application/json")
            if (cookies != null) conn2.setRequestProperty("Cookie", cookies)
            
            val response = conn2.inputStream.bufferedReader().use { it.readText() }
            conn2.disconnect()

            val json = JSONObject(response)
            val dataArray = json.getJSONArray("data")
            
            // 3. Update bookmarked indices in prefs
            val widgetData = HomeWidgetPlugin.getData(context)
            val bookmarks = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getStringSet("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBmaWxlX2luZGV4X2Jvb2ttYXJrcw==", null) 
                // Note: SharedPreferences key in Flutter is base64 encoded prefix + key if using shared_preferences.
                // However, our NavRepository uses SQLite. 
                // We'll rely on the existing 'indices_json' which should be updated by Flutter eventually.
                // BUT the user wants the widget to refresh NOW.
                // To do this properly, Kotlin would need to read the SQLite database.
                
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
                        item.put("chartPath", apiItem.optString("chartTodayPath", ""))
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
        val userCols = widgetData.getInt("user_columns", 0)

        for (appWidgetId in appWidgetIds) {
            val indicesJson = widgetData.getString("indices_json", null)
            val views = RemoteViews(context.packageName, R.layout.index_widget)

            // 1. DUMMY INTENT TO STOP BACKGROUND CLICKS
            val nothingIntent = Intent(context, IndexWidgetProvider::class.java).apply {
                action = ACTION_DO_NOTHING
            }
            val nothingPendingIntent = android.app.PendingIntent.getBroadcast(
                context, 999, nothingIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            // Apply it to anything that shouldn't open the app
            views.setOnClickPendingIntent(R.id.header_bar, nothingPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_title, nothingPendingIntent)
            views.setOnClickPendingIntent(R.id.last_refresh_label, nothingPendingIntent)
            views.setOnClickPendingIntent(R.id.last_refresh, nothingPendingIntent)

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

            // Toggle columns
            val toggleIntent = Intent(context, IndexWidgetProvider::class.java).apply {
                action = ACTION_TOGGLE_COLS
            }
            val togglePendingIntent = android.app.PendingIntent.getBroadcast(
                context, 1, toggleIntent, 
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_toggle_cols, togglePendingIntent)

            // Determine columns
            var columns = 2
            if (userCols != 0) {
                columns = userCols
            } else {
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                columns = if (minWidth != 0 && minWidth < 250) 1 else 2
            }
            
            views.setTextViewText(R.id.btn_toggle_cols, if (userCols == 0) "Auto" else "$columns Col")
            views.setInt(R.id.indices_grid, "setNumColumns", columns)

            // Set up GridView adapter
            val serviceIntent = Intent(context, IndexWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("columns", columns)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.indices_grid, serviceIntent)
            views.setEmptyView(R.id.indices_grid, R.id.empty_view)

            // PendingIntent template for clicks on grid items
            val clickIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val clickPendingIntent = android.app.PendingIntent.getActivity(
                context, 100, clickIntent, 
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setPendingIntentTemplate(R.id.indices_grid, clickPendingIntent)

            if (indicesJson.isNullOrEmpty()) {
                views.setViewVisibility(R.id.empty_view, View.VISIBLE)
                views.setViewVisibility(R.id.indices_grid, View.GONE)
            } else {
                views.setViewVisibility(R.id.empty_view, View.GONE)
                views.setViewVisibility(R.id.indices_grid, View.VISIBLE)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.indices_grid)
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
