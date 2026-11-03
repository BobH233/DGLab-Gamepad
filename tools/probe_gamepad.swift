import Foundation
import GameController
GCController.shouldMonitorBackgroundEvents = true
func inspect() {
    let controllers = GCController.controllers()
    print("GameController devices: \(controllers.count)")
    for c in controllers {
        print("name=\(c.vendorName ?? "unknown") category=\(c.productCategory) extended=\(c.extendedGamepad != nil) micro=\(c.microGamepad != nil)")
        if let p = c.extendedGamepad {
            print("left=(\(p.leftThumbstick.xAxis.value),\(p.leftThumbstick.yAxis.value)) right=(\(p.rightThumbstick.xAxis.value),\(p.rightThumbstick.yAxis.value)) LT=\(p.leftTrigger.value) RT=\(p.rightTrigger.value)")
        }
    }
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
inspect()
