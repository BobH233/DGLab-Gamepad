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
        desk.setAutoScrollToAction(false);
        desk.engine.input(GamepadState.neutral, live: true, deviceId: 'pad');
        desk.engine.input(
          GamepadState({Control.south: 1}),
          live: true,
          deviceId: 'pad',
        );
        desk.toggle('A');
        desk.setTouchGrid(false);
        desk.setTouchBalance('A', 0.8);
        desk.setTouchHorizontalSplits('A', 0.25, 0.7);
        desk.setTouchVerticalSplits('A', 0.3, 0.75);
        await desk.setChannelControls(
          'A',
          linearAmount: 75,
          linearUnit: 'percent',
          boostAmount: 45,
        );
        await desk.setChannelControls(
          'B',
          linearAmount: -20,
          linearUnit: 'absolute',
          boostAmount: 15,
        );
        monitor.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(desk.engine.state.enabled('A'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 750));
        final saved = await store.read();
        expect(saved!['version'], 6);
        expect(saved['autoScrollToAction'], isFalse);
        expect(saved['channels']['A']['base'], 5);
        expect(saved['channels']['A']['linear']['amount'], 75);
        expect(saved['channels']['A']['linear']['unit'], 'percent');
        expect(saved['channels']['A']['boost']['amount'], 45);
        expect(saved['channels']['A'].containsKey('enabled'), isFalse);
        await restored.initialize(storage: store, assets: _Assets());
        expect(restored.ready, isTrue, reason: restored.error);
        expect(restored.actions, contains(action.id));
        expect(restored.bindings.any((b) => b.action == action.id), isTrue);
        expect(restored.engine.state.channels['A']!.base, 5);
        expect(restored.engine.state.enabled('A'), isFalse);
        expect(restored.engine.state.touchGrid, isFalse);
        expect(restored.engine.state.touchBalance['A'], 0.8);
        expect(restored.engine.state.touchHorizontalSplits['A'], [0.25, 0.7]);
        expect(restored.engine.state.touchVerticalSplits['A'], [0.3, 0.75]);
        expect(restored.autoScrollToAction, isFalse);
        expect(restored.engine.state.channels['A']!.linearAmount, 75);
        expect(restored.engine.state.channels['A']!.linearUnit, 'percent');
        expect(restored.engine.state.channels['A']!.boostAmount, 45);
        expect(restored.engine.state.channels['B']!.linearAmount, -20);
        expect(restored.engine.state.channels['B']!.linearUnit, 'absolute');
        expect(restored.engine.state.channels['B']!.boostAmount, 15);
      } finally {
        desk.dispose();
        restored.dispose();
        monitor.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('imported pulse persists above built-ins and restores selection', () async {
    final dir = Directory.systemTemp.createTempSync('dglab-pulse-store-');
    final store = ControlStore(File('${dir.path}/profile.json'));
    final monitor = InputMonitor(
      events: const Stream.empty(),
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor);
    final restored = ControlDesk(monitor);
    try {
      await desk.initialize(storage: store, assets: _Assets());
      final imported = await desk.importPulseWaveform(
        'Dungeonlab+pulse:0,1,16=0,0,0,1,1/0-1,100-1',
        name: '导入波形',
      );

      expect(waveforms.first.id, imported.id);
      expect(waveforms.first.isCustom, isTrue);
      expect(desk.customWaveforms.single.id, imported.id);
      expect(desk.engine.state.channels['A']!.waveform, imported.id);
      final saved = await store.read();
      expect(saved!['version'], 6);
      expect(saved['customWaveforms'], hasLength(1));

      await restored.initialize(storage: store, assets: _Assets());
      expect(restored.ready, isTrue, reason: restored.error);
      expect(waveforms.first.id, imported.id);
      expect(restored.customWaveforms.single.name, '导入波形');
      expect(restored.engine.state.channels['A']!.waveform, imported.id);
      expect(restored.engine.state.channels['A']!.cursor, 0);
    } finally {
      desk.dispose();
      restored.dispose();
      monitor.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'bad restored bindings are skipped without blocking valid ones',
    () async {
      final dir = Directory.systemTemp.createTempSync('dglab-store-');
      final store = ControlStore(File('${dir.path}/profile.json'));
      final valid = ControlDesk.defaultBindings().first.toJson();
      await store.save({
        'version': 2,
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
  test(
    'custom script names persist without changing source or bindings',
    () async {
      final dir = Directory.systemTemp.createTempSync('dglab-script-name-');
      final store = ControlStore(File('${dir.path}/profile.json'));
      final monitor = InputMonitor(
        events: const Stream.empty(),
        observeLifecycle: false,
      );
      final desk = ControlDesk(monitor);
      final restored = ControlDesk(monitor);
      try {
        final source = File('assets/scripts/example.js').readAsStringSync();
        await desk.initialize(storage: store, assets: _Assets());
        final action = desk.validateScript(source);
        await desk.install(action);
        await desk.setBinding(
          Binding(
            id: 'renamed_script',
            input: 'south',
            action: action.id,
            config: action.defaults,
          ),
        );
        await desk.renameScript(action.id, '  我的点按调强  ');

        expect(desk.actions[action.id]!.name, '我的点按调强');
        expect(desk.actions[action.id]!.registeredName, '点按调强');
        desk.engine.input(GamepadState.neutral, live: true, deviceId: 'pad');
        desk.engine.input(
          GamepadState({Control.south: 1}),
          live: true,
          deviceId: 'pad',
        );
        expect(desk.engine.eventLog.first, contains('我的点按调强'));

        final saved = await store.read();
        expect(saved!['version'], 6);
        expect(saved['scripts'], [source]);
        expect(saved['scriptNames'], {action.id: '我的点按调强'});

        await restored.initialize(storage: store, assets: _Assets());
        expect(restored.ready, isTrue, reason: restored.error);
        expect(restored.actions[action.id]!.name, '我的点按调强');
        expect(restored.actions[action.id]!.source, source);
        expect(
          restored.bindings.singleWhere((b) => b.action == action.id).input,
          'south',
        );

        await expectLater(
          desk.renameScript('builtin.boost', '不能改名'),
          throwsFormatException,
        );
        await expectLater(
          desk.renameScript(action.id, '   '),
          throwsFormatException,
        );
        await expectLater(
          desk.renameScript(action.id, '名' * 41),
          throwsFormatException,
        );
        await desk.save();
      } finally {
        desk.dispose();
        restored.dispose();
        monitor.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('version 5 string scripts load with their registered name', () async {
    final dir = Directory.systemTemp.createTempSync('dglab-script-v5-');
    final store = ControlStore(File('${dir.path}/profile.json'));
    final source = File('assets/scripts/example.js').readAsStringSync();
    await store.save({
      'version': 5,
      'scripts': [source],
    });
    final monitor = InputMonitor(
      events: const Stream.empty(),
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor);
    try {
      await desk.initialize(storage: store, assets: _Assets());
      expect(desk.ready, isTrue, reason: desk.error);
      expect(desk.actions['user.stepStrength']!.name, '点按调强');
      expect(desk.actions['user.stepStrength']!.source, source);
    } finally {
      desk.dispose();
      monitor.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('version 1 profiles gain the default Y touch binding', () async {
    final dir = Directory.systemTemp.createTempSync('dglab-migrate-');
    final store = ControlStore(File('${dir.path}/profile.json'));
    await store.save({'version': 1, 'bindings': []});
    final monitor = InputMonitor(
      events: const Stream.empty(),
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor);
    try {
      await desk.initialize(storage: store, assets: _Assets());
      expect(desk.ready, isTrue, reason: desk.error);
      final touch = desk.bindings.singleWhere((b) => b.input == 'north');
      expect(touch.action, 'builtin.toggleTouch');
      expect((await store.read())!['version'], 6);
    } finally {
      desk.dispose();
      monitor.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('version 3 binding amounts migrate into channel controls', () async {
    final dir = Directory.systemTemp.createTempSync('dglab-tuning-migrate-');
    final store = ControlStore(File('${dir.path}/profile.json'));
    final linear =
        ControlDesk.defaultBindings()
            .firstWhere((binding) => binding.action == 'builtin.linear')
            .toJson()
          ..['config'] = {
            'target': 'selected',
            'unit': 'percent',
            'amount': 55,
          };
    final boost =
        ControlDesk.defaultBindings()
            .firstWhere((binding) => binding.action == 'builtin.boost')
            .toJson()
          ..['config'] = {'target': 'selected', 'mode': 'hold', 'amount': 42};
    await store.save({
      'version': 3,
      'bindings': [
        linear,
        boost,
        {
          ...linear,
          'config': {'target': 'A', 'unit': 'absolute', 'amount': 199},
        },
      ],
    });
    final monitor = InputMonitor(
      events: const Stream.empty(),
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor);
    try {
      await desk.initialize(storage: store, assets: _Assets());
      expect(desk.engine.state.channels['A']!.linearAmount, 55);
      expect(desk.engine.state.channels['A']!.linearUnit, 'percent');
      expect(desk.engine.state.channels['A']!.boostAmount, 42);
      expect(desk.engine.state.channels['B']!.linearAmount, 55);
      expect(desk.engine.state.channels['B']!.linearUnit, 'percent');
      expect(desk.engine.state.channels['B']!.boostAmount, 42);
      expect(
        desk.bindings.any((binding) => binding.config.containsKey('amount')),
        isFalse,
      );
      await desk.save();
      final saved = await store.read();
      expect(saved!['version'], 6);
      expect(saved['channels']['A']['linear']['amount'], 55);
      expect(saved['channels']['A']['boost']['amount'], 42);
    } finally {
      desk.dispose();
      monitor.dispose();
      await dir.delete(recursive: true);
    }
  });
}
