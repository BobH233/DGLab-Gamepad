package com.dglab.dglab_gamepad

import android.view.KeyEvent
import android.view.MotionEvent
import com.dglab.gamepad_bridge.GamepadBridgePlugin
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        GamepadBridgePlugin.instance?.onKey(event) == true || super.dispatchKeyEvent(event)

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean =
        GamepadBridgePlugin.instance?.onMotion(event) == true || super.dispatchGenericMotionEvent(event)

    override fun onPause() {
        GamepadBridgePlugin.instance?.resetInputs()
        super.onPause()
    }
}
