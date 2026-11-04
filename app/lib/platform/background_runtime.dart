import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundRuntime {
  static const _channel = MethodChannel('dglab_gamepad/background_runtime');

  static Future<void> setBleConnected(bool connected) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setBleConnected', {
        'connected': connected,
      });
    } on PlatformException catch (error) {
      debugPrint('Background service unavailable: $error');
    } on MissingPluginException {
      debugPrint('Background service is not registered');
    }
  }
}
