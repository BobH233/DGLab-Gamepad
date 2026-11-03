import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad_core/gamepad_core.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/control/control_store.dart';
import 'package:dglab_gamepad/control/models.dart';

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'imported script changes persist and restart restores configuration stopped',
    () async {
      final dir = Directory.systemTemp.createTempSync('dglab-store-');
      final store = ControlStore(File('${dir.path}/profile.json'));
      final monitor = InputMonitor(
        events: const Stream.empty(),
        observeLifecycle: false,
      );
      final desk = ControlDesk(monitor);
      final restored = ControlDesk(monitor);
      try {
        await desk.initialize(storage: store, assets: _Assets());
        final action = desk.validateScript(
          File('assets/scripts/example.js').readAsStringSync(),
        );
        await desk.install(action);
        await desk.setBinding(
          Binding(
            id: 'custom',
            input: 'south',
            action: action.id,
            config: action.defaults,
          ),
        );
        desk.engine.input(GamepadState.neutral, live: true, deviceId: 'pad');
        desk.engine.input(
          GamepadState({Control.south: 1}),
          live: true,
          deviceId: 'pad',
        );
        desk.toggle('A');
        monitor.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(desk.engine.state.enabled('A'), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 750));
        final saved = await store.read();
        expect(saved!['channels']['A']['base'], 5);
        expect(saved['channels']['A'].containsKey('enabled'), isFalse);
        await restored.initialize(storage: store, assets: _Assets());
        expect(restored.ready, isTrue, reason: restored.error);
        expect(restored.actions, contains(action.id));
        expect(restored.bindings.any((b) => b.action == action.id), isTrue);
        expect(restored.engine.state.channels['A']!.base, 5);
        expect(restored.engine.state.enabled('A'), isFalse);
      } finally {
        desk.dispose();
        restored.dispose();
        monitor.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'bad restored bindings are skipped without blocking valid ones',
    () async {
      final dir = Directory.systemTemp.createTempSync('dglab-store-');
      final store = ControlStore(File('${dir.path}/profile.json'));
      final valid = ControlDesk.defaultBindings().first.toJson();
      await store.save({
        'version': 1,
        'bindings': [
          valid,
          valid,
          {...valid, 'id': 'bad', 'input': 'nonexistent'},
        ],
      });
      final monitor = InputMonitor(
        events: const Stream.empty(),
        observeLifecycle: false,
      );
      final desk = ControlDesk(monitor);
      try {
        await desk.initialize(storage: store, assets: _Assets());
        expect(desk.ready, isTrue, reason: desk.error);
        expect(desk.bindings, hasLength(1));
        expect(desk.loadWarnings, hasLength(2));
      } finally {
        desk.dispose();
        monitor.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
