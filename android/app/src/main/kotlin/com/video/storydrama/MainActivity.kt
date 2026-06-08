package com.video.storydrama

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.video.storydrama/restart"
    private val TAG = "AppRestart"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "restart") {
                    restartApp()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun restartApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TASK or
            Intent.FLAG_ACTIVITY_NO_ANIMATION
        )

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_CANCEL_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            1001,
            launchIntent,
            pendingIntentFlags
        )

        Log.d(TAG, "restart requested, scheduling relaunch")

        try {
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "startActivity relaunch failed", e)
        }

        val alarmManager = getSystemService(AlarmManager::class.java)
        val triggerAtMillis = System.currentTimeMillis() + 800

        if (alarmManager != null) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC,
                triggerAtMillis,
                pendingIntent
            )
        } else {
            try {
                pendingIntent.send()
            } catch (e: Exception) {
                Log.e(TAG, "pendingIntent relaunch failed", e)
            }
        }

        finishAffinity()
        finishAndRemoveTask()
        android.os.Process.killProcess(android.os.Process.myPid())
    }
}
