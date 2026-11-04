import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// State of the iOS silent-audio keep-alive. Android's foreground service
/// has no equivalent failure mode and always reports [unsupported].
enum KeepAliveState {
  /// The platform does not need or report a keep-alive state.
  unsupported,

  /// Not requested.
  idle,

  /// Requested and holding the app in the background.
  running,

  /// Requested, but the system took the audio session away (call, Siri,
  /// alarm, media-services reset). The app may be suspended in the
  /// background until it recovers.
  interrupted;

  static KeepAliveState parse(Object? value) => switch (value) {
    'idle' => idle,
    'running' => running,
    'interrupted' => interrupted,
    _ => unsupported,
  };
}

abstract final class BackgroundRuntime {
  static const _channel = MethodChannel('dglab_gamepad/background_runtime');
  static final _keepAlive = ValueNotifier(KeepAliveState.unsupported);
  static bool _listening = false;

  /// Live keep-alive state pushed from the platform.
  static ValueListenable<KeepAliveState> get keepAlive {
    _listen();
    return _keepAlive;
  }

  static void _listen() {
    if (_listening || kIsWeb || !Platform.isIOS) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'keepAliveStateChanged') {
        _keepAlive.value = KeepAliveState.parse(call.arguments);
      }
    });
  }

  /// Keeps the process alive in the background while a Coyote is connected:
  /// a foreground service on Android, background audio on iOS.
  static Future<void> setBleConnected(bool connected) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    _listen();
    try {
      final state = await _channel.invokeMethod<Object?>('setBleConnected', {
        'connected': connected,
      });
      if (Platform.isIOS) _keepAlive.value = KeepAliveState.parse(state);
    } on PlatformException catch (error) {
      debugPrint('Background service unavailable: $error');
    } on MissingPluginException {
      debugPrint('Background service is not registered');
    }
  }
}
