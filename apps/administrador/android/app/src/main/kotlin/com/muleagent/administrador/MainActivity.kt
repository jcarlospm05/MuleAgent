package com.muleagent.administrador

import android.content.Intent
import android.os.Bundle
import com.muleagent.platform.IncomingReports
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var incoming: IncomingReports? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incoming = IncomingReports(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        incoming?.receive(intent)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incoming?.receive(intent)
    }
    override fun onDestroy() {
        incoming?.close()
        incoming = null
        super.onDestroy()
    }
}
