import Foundation
import GameController
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

public class GamepadBridgePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var identities: [ObjectIdentifier: String] = [:]
    private var sequence = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(macOS)
        let messenger = registrar.messenger
        #else
        let messenger = registrar.messenger()
        #endif
        let channel = FlutterEventChannel(name: "com.dglab.gamepad/events", binaryMessenger: messenger)
        channel.setStreamHandler(GamepadBridgePlugin())
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        #if os(macOS)
        GCController.shouldMonitorBackgroundEvents = false
        #endif
        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.attachControllers()
                self?.emit()
            })
        }
        attachControllers()
        emit()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.emit() }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
            controller.microGamepad?.valueChangedHandler = nil
        }
        identities.removeAll()
        sink = nil
        return nil
    }

    private func attachControllers() {
        let controllers = GCController.controllers()
        let current = Set(controllers.map { ObjectIdentifier($0) })
        identities = identities.filter { current.contains($0.key) }
        for controller in controllers {
            let key = ObjectIdentifier(controller)
            if identities[key] == nil { identities[key] = UUID().uuidString }
            controller.handlerQueue = .main
            if let pad = controller.extendedGamepad {
                pad.buttonOptions?.preferredSystemGestureState = .disabled
                (pad as? GCXboxGamepad)?.buttonShare?.preferredSystemGestureState = .disabled
                pad.valueChangedHandler = { [weak self] _, _ in self?.emit() }
            } else if let pad = controller.microGamepad {
                pad.valueChangedHandler = { [weak self] _, _ in self?.emit() }
            }
        }
    }

    private func snapshot(_ controller: GCController) -> [String: Any] {
        var values: [String: Double] = [:]
        func button(_ name: String, _ input: GCControllerButtonInput?) {
            if let input = input { values[name] = Double(input.value) }
        }
        func direction(_ input: GCControllerDirectionPad) {
            button("up", input.up); button("down", input.down)
            button("left", input.left); button("right", input.right)
        }
        if let pad = controller.extendedGamepad {
            button("south", pad.buttonA); button("east", pad.buttonB)
            button("west", pad.buttonX); button("north", pad.buttonY)
            button("leftShoulder", pad.leftShoulder); button("rightShoulder", pad.rightShoulder)
            button("leftTrigger", pad.leftTrigger); button("rightTrigger", pad.rightTrigger)
            button("leftStick", pad.leftThumbstickButton); button("rightStick", pad.rightThumbstickButton)
            button("menu", pad.buttonMenu); button("view", pad.buttonOptions); button("home", pad.buttonHome)
            values["leftX"] = Double(pad.leftThumbstick.xAxis.value)
            values["leftY"] = -Double(pad.leftThumbstick.yAxis.value)
            values["rightX"] = Double(pad.rightThumbstick.xAxis.value)
            values["rightY"] = -Double(pad.rightThumbstick.yAxis.value)
            direction(pad.dpad)
        } else if let pad = controller.microGamepad {
            button("south", pad.buttonA); button("west", pad.buttonX)
            button("menu", pad.buttonMenu)
            direction(pad.dpad)
        }
        let category = controller.productCategory
        let family: String
        if category.lowercased().contains("xbox") { family = "xbox" }
        else if category.lowercased().contains("dual") { family = "playstation" }
        else if category.lowercased().contains("switch") { family = "nintendo" }
        else { family = "generic" }
        let key = ObjectIdentifier(controller)
        if identities[key] == nil { identities[key] = UUID().uuidString }
        var result: [String: Any] = [
            "id": identities[key]!, "name": controller.vendorName ?? "Gamepad",
            "family": family, "transport": "GameController", "category": category,
            "capabilities": Array(values.keys).sorted(), "values": values,
        ]
        if let battery = controller.battery, battery.batteryLevel >= 0 {
            result["battery"] = Double(battery.batteryLevel)
        }
        return result
    }

    private func emit() {
        guard let sink = sink else { return }
        sequence += 1
        sink([
            "version": 1, "type": "snapshot", "sequence": sequence,
            "devices": GCController.controllers().map(snapshot),
        ])
    }
}
