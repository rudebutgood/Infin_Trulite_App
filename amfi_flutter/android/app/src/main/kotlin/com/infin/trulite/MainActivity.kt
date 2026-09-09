package com.infin.trulite

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.infin.trulite/deep_link"
    private var pendingIndexName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialIndex") {
                result.success(pendingIndexName)
                pendingIndexName = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        intent?.let { handleIntent(it) }
    }

    private fun handleIntent(intent: Intent) {
        if (Intent.ACTION_VIEW == intent.action) {
            val data: Uri? = intent.data
            if (data != null && "infin-trulite" == data.scheme && "indices" == data.host) {
                val indexName = data.getQueryParameter("name")
                if (indexName != null) {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let {
                        MethodChannel(it, CHANNEL).invokeMethod("openIndex", indexName)
                    } ?: run {
                        pendingIndexName = indexName
                    }
                }
            }
        }
    }
}
