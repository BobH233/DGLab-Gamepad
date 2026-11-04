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
    private var pendingBluetoothResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A fresh engine has no BLE connection yet; drop any service left over
        // from a previous engine so it does not keep holding the wake lock.
        stopService(Intent(this, CoyoteForegroundService::class.java))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dglab_gamepad/background_runtime"
        ).setMethodCallHandler { call, result ->
            if (call.method != "setBleConnected") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            setBleConnected(call.argument<Boolean>("connected") == true, result)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dglab_gamepad/bluetooth_permissions"
        ).setMethodCallHandler { call, result ->
            if (call.method != "request") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            requestBluetoothPermissions(result)
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

    private fun setBleConnected(connected: Boolean, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, CoyoteForegroundService::class.java)
            if (connected) {
                if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    !isGranted(Manifest.permission.POST_NOTIFICATIONS)
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

    private fun bluetoothPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun isGranted(permission: String) =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        val missing = bluetoothPermissions().filterNot(::isGranted)
        if (missing.isEmpty()) {
            result.success(permissionState())
            return
        }
        if (pendingBluetoothResult != null) {
            result.error("permission_busy", "Bluetooth permission request already running", null)
            return
        }
        pendingBluetoothResult = result
        requestPermissions(missing.toTypedArray(), BLUETOOTH_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != BLUETOOTH_PERMISSION_REQUEST) return
        val result = pendingBluetoothResult ?: return
        pendingBluetoothResult = null
        // An empty result means the request was interrupted; re-check the real state.
        result.success(permissionState())
    }

    // Android 12+ declares BLUETOOTH_SCAN with neverForLocation, so scanning
    // no longer depends on the system location switch.
    private fun permissionState(): Map<String, Boolean> = mapOf(
        "granted" to bluetoothPermissions().all(::isGranted),
        "locationServicesRequired" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S)
    )

    override fun onDestroy() {
        pendingBluetoothResult?.success(permissionState())
        pendingBluetoothResult = null
        super.onDestroy()
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
        private const val BLUETOOTH_PERMISSION_REQUEST = 4103
    }
}
