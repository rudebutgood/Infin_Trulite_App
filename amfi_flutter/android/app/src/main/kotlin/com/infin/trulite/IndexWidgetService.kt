package com.infin.trulite

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import android.view.View
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import com.caverock.androidsvg.SVG
import java.net.URL
import java.net.HttpURLConnection

class IndexWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return IndexWidgetFactory(applicationContext, intent)
    }
}

class IndexWidgetFactory(private val context: Context, private val intent: Intent) : RemoteViewsService.RemoteViewsFactory {
    private var indices: JSONArray = JSONArray()
    private var columns: Int = 2
    private val chartCache = mutableMapOf<String, Bitmap>()

    override fun onCreate() {
        columns = intent.getIntExtra("columns", 2)
    }

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        val indicesJson = widgetData.getString("indices_json", null)
        indices = if (indicesJson.isNullOrEmpty()) JSONArray() else JSONArray(indicesJson)
        columns = intent.getIntExtra("columns", 2)
        // Clear cache on refresh
        chartCache.clear()
    }

    override fun onDestroy() {
        chartCache.values.forEach { it.recycle() }
        chartCache.clear()
    }

    override fun getCount(): Int = indices.length()

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.index_item_row)
        
        try {
            val item = indices.getJSONObject(position)
            val name = item.getString("name")
            val last = item.getString("last")
            val change = item.getString("change")
            val isPositive = item.getBoolean("isPositive")
            val chartPath = item.optString("chartPath", "")

            views.setTextViewText(R.id.index_name, name)
            views.setTextViewText(R.id.index_value, last)
            views.setTextViewText(R.id.index_change, (if (isPositive) "+" else "") + change + "%")
            
            // Funds Page colors: Green 700 (#388E3C), Red 700 (#D32F2F)
            val color = if (isPositive) 0xFF388E3C.toInt() else 0xFFD32F2F.toInt()
            views.setTextColor(R.id.index_change, color)

            if (columns == 1 && chartPath.isNotEmpty()) {
                views.setViewVisibility(R.id.index_chart, View.VISIBLE)
                val bitmap = getChartBitmap(chartPath, isPositive)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.index_chart, bitmap)
                }
            } else {
                views.setViewVisibility(R.id.index_chart, View.GONE)
            }

            // Fill-in intent for deep linking
            val fillInIntent = Intent().apply {
                val dataUri = Uri.parse("infin-trulite://indices?name=${Uri.encode(name)}")
                data = dataUri
                // Also add as extra just in case
                putExtra("indexName", name)
            }
            views.setOnClickFillInIntent(R.id.row_container, fillInIntent)
            
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return views
    }

    private fun getChartBitmap(path: String, isPositive: Boolean): Bitmap? {
        if (chartCache.containsKey(path)) return chartCache[path]

        try {
            val fullUrl = if (path.startsWith("http")) path else "https://www.nseindia.com$path"
            val url = URL(fullUrl)
            val conn = url.openConnection() as HttpURLConnection
            conn.setRequestProperty("User-Agent", "Mozilla/5.0")
            conn.connect()
            
            val svgString = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()

            if (svgString.contains("<svg")) {
                val svg = SVG.getFromString(svgString)

                // Color the SVG based on trend: Green 700 (#388E3C), Red 700 (#D32F2F)
                val colorStr = if (isPositive) "#388E3C" else "#D32F2F"

                // SVG dimensions for a small sparkline
                val width = 120
                val height = 48
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)

                // Scale SVG to fit our bitmap
                svg.documentWidth = width.toFloat()
                svg.documentHeight = height.toFloat()

                svg.renderToCanvas(canvas)

                chartCache[path] = bitmap
                return bitmap
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
