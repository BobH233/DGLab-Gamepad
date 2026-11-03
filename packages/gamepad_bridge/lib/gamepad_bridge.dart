import 'package:flutter/services.dart';

class GamepadBridge {
  static const _events = EventChannel('com.dglab.gamepad/events');
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));
}
