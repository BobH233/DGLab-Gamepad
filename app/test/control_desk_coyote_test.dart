import 'dart:io';

import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/control/control_store.dart';
import 'package:dglab_gamepad/coyote/coyote_controller.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

class _LossyCoyote extends CoyoteController {
  void simulateLoss() => onUnexpectedDisconnect?.call();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('losing the Coyote link stops every channel', () async {
    final dir = Directory.systemTemp.createTempSync('dglab-desk-');
    final monitor = InputMonitor(
      events: const Stream.empty(),
      observeLifecycle: false,
    );
    final coyote = _LossyCoyote();
    final desk = ControlDesk(monitor, coyote: coyote);
    try {
      await desk.initialize(
        storage: ControlStore(File('${dir.path}/profile.json')),
        assets: _Assets(),
      );
      desk.setBase('A', 60, persist: false);
      desk.startAll();
      expect(desk.engine.state.enabled('A'), isTrue);

      coyote.simulateLoss();

      expect(desk.engine.state.enabled('A'), isFalse);
      expect(desk.engine.state.enabled('B'), isFalse);
      expect(desk.engine.state.channels['A']!.base, 60);
    } finally {
      desk.dispose();
      monitor.dispose();
      dir.deleteSync(recursive: true);
    }
  });
}
