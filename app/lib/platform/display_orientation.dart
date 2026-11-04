import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NavigationRailSide { left, right }

abstract final class DisplayOrientation {
  static const _channel = MethodChannel('dglab_gamepad/display_orientation');

  static Future<NavigationRailSide?> navigationSide() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return null;
    }
    try {
      final side = await _channel.invokeMethod<String>('navigationSide');
      return switch (side) {
        'left' => NavigationRailSide.left,
        'right' => NavigationRailSide.right,
        _ => null,
      };
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
