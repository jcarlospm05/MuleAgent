package com.muleagent.operador

import android.content.Intent
import android.os.Bundle
import com.muleagent.platform.IncomingReports
import com.muleagent.platform.PublicReports
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var reports: PublicReports? = null
    private var incoming: IncomingReports? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reports = PublicReports(this, flutterEngine.dartExecutor.binaryMessenger)
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
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (reports?.permissionResult(requestCode) != true) super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
    override fun onDestroy() {
        incoming?.close()
        incoming = null
        reports?.close()
        reports = null
        super.onDestroy()
    }
}
