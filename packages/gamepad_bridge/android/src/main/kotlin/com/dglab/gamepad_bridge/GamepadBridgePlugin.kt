package com.dglab.gamepad_bridge

import android.content.Context
import android.hardware.input.InputManager
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import java.util.UUID

class GamepadBridgePlugin : FlutterPlugin, EventChannel.StreamHandler, InputManager.InputDeviceListener {
    companion object {
        var instance: GamepadBridgePlugin? = null
            private set
        private val keys = mapOf(
            KeyEvent.KEYCODE_BUTTON_A to "south", KeyEvent.KEYCODE_BUTTON_B to "east",
            KeyEvent.KEYCODE_BUTTON_X to "west", KeyEvent.KEYCODE_BUTTON_Y to "north",
            KeyEvent.KEYCODE_BUTTON_L1 to "leftShoulder", KeyEvent.KEYCODE_BUTTON_R1 to "rightShoulder",
            KeyEvent.KEYCODE_BUTTON_L2 to "leftTrigger", KeyEvent.KEYCODE_BUTTON_R2 to "rightTrigger",
            KeyEvent.KEYCODE_BUTTON_THUMBL to "leftStick", KeyEvent.KEYCODE_BUTTON_THUMBR to "rightStick",
            KeyEvent.KEYCODE_BUTTON_START to "menu", KeyEvent.KEYCODE_BUTTON_SELECT to "view",
            KeyEvent.KEYCODE_BUTTON_MODE to "home",
            KeyEvent.KEYCODE_DPAD_UP to "up", KeyEvent.KEYCODE_DPAD_DOWN to "down",
            KeyEvent.KEYCODE_DPAD_LEFT to "left", KeyEvent.KEYCODE_DPAD_RIGHT to "right",
        )
        private fun isGamepad(d: InputDevice) = !d.isVirtual &&
            (d.supportsSource(InputDevice.SOURCE_GAMEPAD) || d.supportsSource(InputDevice.SOURCE_JOYSTICK))
    }
    private lateinit var manager: InputManager
    private lateinit var channel: EventChannel
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val identities = mutableMapOf<Int, String>()
    private val digital = mutableMapOf<Int, MutableMap<String, Double>>()
    private val analog = mutableMapOf<Int, MutableMap<String, Double>>()
    private var sequence = 0L
    private val heartbeat = object : Runnable {
        override fun run() { emit(); handler.postDelayed(this, 250) }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instance = this
        manager = binding.applicationContext.getSystemService(Context.INPUT_SERVICE) as InputManager
        channel = EventChannel(binding.binaryMessenger, "com.dglab.gamepad/events")
        channel.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        onCancel(null); channel.setStreamHandler(null)
        if (instance === this) instance = null
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        manager.registerInputDeviceListener(this, handler)
        heartbeat.run()
    }
    override fun onCancel(arguments: Any?) {
        handler.removeCallbacks(heartbeat)
        manager.unregisterInputDeviceListener(this)
        sink = null; digital.clear(); analog.clear(); identities.clear()
    }
    override fun onInputDeviceAdded(deviceId: Int) { emit() }
    override fun onInputDeviceRemoved(deviceId: Int) {
        digital.remove(deviceId); analog.remove(deviceId); identities.remove(deviceId); emit()
    }
    override fun onInputDeviceChanged(deviceId: Int) {
        digital.remove(deviceId); analog.remove(deviceId); identities.remove(deviceId); emit()
    }

    fun resetInputs() { digital.clear(); analog.clear(); emit() }

    fun onKey(event: KeyEvent): Boolean {
        val device = event.device ?: return false
        if (!isGamepad(device) || sink == null) return false
        val control = keys[event.keyCode] ?: return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false
        digital.getOrPut(device.id) { mutableMapOf() }[control] =
            if (event.action == KeyEvent.ACTION_DOWN) 1.0 else 0.0
        emit()
        return true
    }

    private fun axes(device: InputDevice): Map<String, Int> {
        fun available(axis: Int) = device.getMotionRange(axis, InputDevice.SOURCE_JOYSTICK) != null
        val result = mutableMapOf<String, Int>()
        fun pick(name: String, vararg candidates: Int) {
            candidates.firstOrNull { available(it) }?.let { result[name] = it }
        }
        pick("leftX", MotionEvent.AXIS_X); pick("leftY", MotionEvent.AXIS_Y)
        if (available(MotionEvent.AXIS_Z) && available(MotionEvent.AXIS_RZ)) {
            result["rightX"] = MotionEvent.AXIS_Z; result["rightY"] = MotionEvent.AXIS_RZ
        } else {
            pick("rightX", MotionEvent.AXIS_RX); pick("rightY", MotionEvent.AXIS_RY)
        }
        pick("leftTrigger", MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_BRAKE)
        pick("rightTrigger", MotionEvent.AXIS_RTRIGGER, MotionEvent.AXIS_GAS)
        pick("hatX", MotionEvent.AXIS_HAT_X); pick("hatY", MotionEvent.AXIS_HAT_Y)
        return result
    }
    fun onMotion(event: MotionEvent): Boolean {
        val device = event.device ?: return false
        if (!isGamepad(device) || !event.isFromSource(InputDevice.SOURCE_JOYSTICK) ||
            event.action != MotionEvent.ACTION_MOVE || sink == null) return false
        val values = analog.getOrPut(device.id) { mutableMapOf() }
        for ((control, axis) in axes(device)) {
            val range = device.getMotionRange(axis, InputDevice.SOURCE_JOYSTICK) ?: continue
            val raw = event.getAxisValue(axis)
            val value = if (!raw.isFinite()) 0.0 else if (control.endsWith("Trigger")) {
                if (range.range > 0) ((raw - range.min) / range.range).toDouble().coerceIn(0.0, 1.0) else 0.0
            } else {
                val scale = if (raw < 0) -range.min else range.max
                if (scale > 0) (raw / scale).toDouble().coerceIn(-1.0, 1.0) else 0.0
            }
            when (control) {
                "hatX" -> { values["left"] = maxOf(0.0, -value); values["right"] = maxOf(0.0, value) }
                "hatY" -> { values["up"] = maxOf(0.0, -value); values["down"] = maxOf(0.0, value) }
                else -> values[control] = value
            }
        }
        emit()
        return true
    }
    private fun snapshot(device: InputDevice): Map<String, Any> {
        val mapping = axes(device)
        val supportedKeys = device.hasKeys(*keys.keys.toIntArray())
        val capabilities = keys.entries.filterIndexed { i, _ -> supportedKeys[i] }
            .map { it.value }.toMutableSet()
        capabilities.addAll(mapping.keys.filter { !it.startsWith("hat") })
        if (mapping.containsKey("hatX")) capabilities.addAll(listOf("left", "right"))
        if (mapping.containsKey("hatY")) capabilities.addAll(listOf("up", "down"))
        val values = capabilities.associateWith { 0.0 }.toMutableMap()
        values.putAll(analog[device.id] ?: emptyMap())
        for ((key, value) in digital[device.id] ?: emptyMap()) {
            if (!key.endsWith("Trigger") || !mapping.containsKey(key)) {
                values[key] = maxOf(values[key] ?: 0.0, value)
            }
        }
        val family = when (device.vendorId) {
            0x045e -> "xbox"
            0x054c -> "playstation"
            0x057e -> "nintendo"
            else -> "generic"
        }
        return mapOf(
            "id" to identities.getOrPut(device.id) { UUID.randomUUID().toString() },
            "name" to device.name, "family" to family, "transport" to "Android InputDevice",
            "vendorId" to device.vendorId, "productId" to device.productId,
            "capabilities" to (capabilities + values.keys).toList().sorted(), "values" to values,
            "axisRanges" to device.motionRanges.map { mapOf(
                "axis" to it.axis, "min" to it.min, "max" to it.max, "flat" to it.flat,
            ) },
        )
    }
    private fun emit() {
        sink?.success(mapOf(
            "version" to 1, "type" to "snapshot", "sequence" to ++sequence,
            "devices" to InputDevice.getDeviceIds().mapNotNull { InputDevice.getDevice(it) }
                .filter { isGamepad(it) }.map { snapshot(it) },
        ))
    }
}
