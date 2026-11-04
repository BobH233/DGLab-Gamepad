package com.dglab.dglab_gamepad

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import com.dglab.gamepad_bridge.GamepadBridgePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dglab_gamepad/background_runtime"
        ).setMethodCallHandler { call, result ->
            if (call.method != "setBleConnected") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val connected = call.argument<Boolean>("connected") == true
            try {
                val intent = Intent(this, CoyoteForegroundService::class.java)
                if (connected) {
                    if (
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFICATION_PERMISSION_REQUEST
                        )
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                } else {
                    stopService(intent)
                }
                result.success(null)
            } catch (error: Exception) {
                result.error("foreground_service", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dglab_gamepad/display_orientation"
        ).setMethodCallHandler { call, result ->
            if (call.method != "navigationSide") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                this.display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            result.success(
                when (currentDisplay?.rotation) {
                    Surface.ROTATION_90 -> "left"
                    Surface.ROTATION_270 -> "right"
                    else -> null
                }
            )
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        GamepadBridgePlugin.instance?.onKey(event) == true || super.dispatchKeyEvent(event)

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean =
        GamepadBridgePlugin.instance?.onMotion(event) == true || super.dispatchGenericMotionEvent(event)

    override fun onPause() {
        GamepadBridgePlugin.instance?.resetInputs()
        super.onPause()
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 4102
    }
}
