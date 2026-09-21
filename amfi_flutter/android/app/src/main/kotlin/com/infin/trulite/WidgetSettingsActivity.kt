package com.infin.trulite

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.RadioGroup
import es.antonborri.home_widget.HomeWidgetPlugin

class WidgetSettingsActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.activity_widget_settings)

        val widgetData = HomeWidgetPlugin.getData(this)
        val currentCols = widgetData.getInt("user_columns_$appWidgetId", widgetData.getInt("user_columns", 2))

        val radioGroup = findViewById<RadioGroup>(R.id.columns_radio_group)
        when (currentCols) {
            1 -> radioGroup.check(R.id.radio_1_col)
            3 -> radioGroup.check(R.id.radio_3_col)
            else -> radioGroup.check(R.id.radio_2_col)
        }

        findViewById<Button>(R.id.btn_save).setOnClickListener {
            val selectedCols = when (radioGroup.checkedRadioButtonId) {
                R.id.radio_1_col -> 1
                R.id.radio_3_col -> 3
                else -> 2
            }

            widgetData.edit()
                .putInt("user_columns_$appWidgetId", selectedCols)
                .putInt("user_columns", selectedCols)
                .commit() // Use commit() instead of apply() to write synchronously to the disk immediately!

            val appWidgetManager = AppWidgetManager.getInstance(this)
            
            // Synchronously apply properties to the RemoteViews layout setup first
            IndexWidgetProvider().onUpdate(this, appWidgetManager, intArrayOf(appWidgetId))

            // Determine the target active grid view ID to fire data change immediately
            val activeGridId = when (selectedCols) {
                1 -> R.layout.index_widget_1col // Note: layout reference converted mapping to grid view ID
                3 -> R.layout.index_widget_3col
                else -> R.layout.index_widget
            }
            val targetGridId = when (selectedCols) {
                1 -> R.id.indices_grid_1col
                3 -> R.id.indices_grid_3col
                else -> R.id.indices_grid_2col
            }

            // Asynchronously broadcast to guarantee system launcher layout binder state sync
            val updateIntent = Intent(this, IndexWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
            }
            sendBroadcast(updateIntent)

            // Force completely recreate adapter views factory dataset cache layers inside framework on the matching Grid ID
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, targetGridId)

            val resultValue = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            setResult(RESULT_OK, resultValue)
            finish()
        }
    }
}
