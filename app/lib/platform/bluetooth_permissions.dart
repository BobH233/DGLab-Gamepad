import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef BluetoothPermissionState = ({
  bool granted,
  bool locationServicesRequired,
});

abstract final class BluetoothPermissions {
  static const _channel = MethodChannel('dglab_gamepad/bluetooth_permissions');

  /// Requests the runtime permissions needed to scan for and connect to BLE
  /// devices. Only Android needs an explicit request; Apple platforms prompt
  /// through CoreBluetooth on first use.
  static Future<BluetoothPermissionState> request() async {
    if (kIsWeb || !Platform.isAndroid) {
      return (granted: true, locationServicesRequired: false);
    }
    try {
      final value = await _channel.invokeMapMethod<String, bool>('request');
      return (
        granted: value?['granted'] ?? false,
        locationServicesRequired: value?['locationServicesRequired'] ?? true,
      );
    } on PlatformException catch (error) {
      debugPrint('Bluetooth permission request failed: $error');
      return (granted: false, locationServicesRequired: true);
    } on MissingPluginException {
      return (granted: false, locationServicesRequired: true);
    }
  }
}
