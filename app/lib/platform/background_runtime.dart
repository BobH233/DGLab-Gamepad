import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundRuntime {
  static const _channel = MethodChannel('dglab_gamepad/background_runtime');

  /// Keeps the process alive in the background while a Coyote is connected:
  /// a foreground service on Android, background audio on iOS.
  static Future<void> setBleConnected(bool connected) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
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
