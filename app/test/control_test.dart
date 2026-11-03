import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad_core/gamepad_core.dart';
import 'package:dglab_gamepad/control/control_engine.dart';
import 'package:dglab_gamepad/control/control_state.dart';
import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/scripting/action_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, ActionDefinition> definitions;
  late ControlEngine engine;
  setUp(() {
    definitions = {};
    for (final name in [
      'boost',
      'linear',
      'select',
      'toggle',
      'waveform',
      'navigate',
      'stick_strength',
      'stick_cursor',
      'confirm',
    ]) {
      final runtime = ActionRuntime(
        File('assets/actions/$name.js').readAsStringSync(),
        builtin: true,
      );
      definitions[runtime.definition.id] = runtime.definition;
      runtime.dispose();
    }
    engine = ControlEngine(output: PreviewOutputSink());
  });
  tearDown(() => engine.dispose());
  void configure(List<Binding> bindings) {
    engine.configure(bindings, definitions);
    engine.input(GamepadState.neutral, live: true, deviceId: 'pad');
  }

  void input(Map<Control, double> values) =>
      engine.input(GamepadState(values), live: true, deviceId: 'pad');
  Binding binding(String input, String action, Map<String, dynamic> config) =>
      Binding(
        id: input,
        input: input,
        action: 'builtin.$action',
        config: {...definitions['builtin.$action']!.defaults, ...config},
      );

  test('DG-LAB presets decode pulse frequency and strength data', () {
    expect(waveforms, hasLength(16));
    final breathe = waveforms.first;
    expect(breathe.id, 'd6f83af0');
    expect(breathe.name, '呼吸');
    expect(breathe.pulseData, hasLength(12));
    expect(breathe.samples, hasLength(48));
    expect(breathe.samples[4].frequency, 10);
    expect(breathe.samples[4].strength, 20);
  });

  test(
    'real JS: base 80 plus 80% at full trigger is 144 and release is 80',
    () {
      configure([
        binding('leftTrigger', 'linear', {
          'target': 'A',
          'unit': 'percent',
          'amount': 80,
        }),
      ]);
      engine.state.channels['A']!.base = 80;
      input({Control.leftTrigger: 1});
      expect(engine.state.effective('A'), 144);
      input({Control.leftTrigger: 0.5});
      expect(engine.state.effective('A'), 112);
      input({});
      expect(engine.state.effective('A'), 80);
    },
  );
  test('negative 100% reaches zero; base does not change', () {
    configure([
      binding('leftTrigger', 'linear', {
        'target': 'A',
        'unit': 'percent',
        'amount': -100,
      }),
    ]);
    engine.state.channels['A']!.base = 80;
    input({Control.leftTrigger: 1});
    expect(engine.state.effective('A'), 0);
    input({});
    expect(engine.state.channels['A']!.base, 80);
  });
  test(
    'two independent offsets stack, clamp, and release without corrupting base',
    () {
      configure([
        binding('leftTrigger', 'linear', {'target': 'A', 'amount': 50}),
        binding('leftShoulder', 'boost', {'target': 'A', 'amount': 40}),
      ]);
      engine.state.channels['A']!.base = 150;
      input({Control.leftTrigger: 0.5, Control.leftShoulder: 1});
      expect(engine.state.effective('A'), 200);
      input({Control.leftTrigger: 0.5});
      expect(engine.state.effective('A'), 175);
      input({});
      expect(engine.state.effective('A'), 150);
    },
  );
  test('selected channel captured for the whole trigger gesture', () {
    configure([
      binding('leftTrigger', 'linear', {'target': 'selected', 'amount': 30}),
      binding('view', 'select', {'channel': 'toggle'}),
    ]);
    input({Control.leftTrigger: 0.5});
    expect(engine.state.offset('A'), 15);
    input({Control.leftTrigger: 0.5, Control.view: 1});
    expect(engine.state.selected, 'B');
    input({Control.leftTrigger: 1});
    expect(engine.state.offset('A'), 30);
    expect(engine.state.offset('B'), 0);
    input({});
    input({Control.leftTrigger: 1});
    expect(engine.state.offset('B'), 30);
  });
  test(
    'toggle fire releases on second press even after changing selection',
    () {
      configure([
        binding('leftShoulder', 'boost', {
          'target': 'selected',
          'amount': 30,
          'mode': 'toggle',
        }),
      ]);
      input({Control.leftShoulder: 1});
      input({});
      engine.state.selected = 'B';
      expect(engine.state.offset('A'), 30);
      input({Control.leftShoulder: 1});
      expect(engine.state.offset('A'), 0);
      expect(engine.state.offset('B'), 0);
    },
  );
  test(
    'hold toggle restores original enabled state and preserves intensity',
    () {
      configure([
        binding('rightShoulder', 'toggle', {'target': 'A', 'mode': 'hold'}),
      ]);
      engine.state.channels['A']!
        ..base = 80
        ..enabled = true;
      input({Control.rightShoulder: 1});
      expect(engine.state.enabled('A'), false);
      input({});
      expect(engine.state.enabled('A'), true);
      expect(engine.state.channels['A']!.base, 80);
    },
  );
  test('trigger button fallback has hysteresis and one edge per crossing', () {
    configure([
      binding('leftTrigger', 'select', {'channel': 'toggle'}),
    ]);
    input({Control.leftTrigger: 0.56});
    expect(engine.state.selected, 'B');
    input({Control.leftTrigger: 0.53});
    input({Control.leftTrigger: 0.56});
    expect(engine.state.selected, 'B');
    input({Control.leftTrigger: 0.3});
    input({Control.leftTrigger: 0.56});
    expect(engine.state.selected, 'A');
  });
  test(
    'cursor movement uses displayed columns and confirm applies only on press',
    () {
      configure([
        binding('down', 'navigate', {'direction': 'down'}),
        binding('south', 'confirm', {}),
      ]);
      engine.state.columns = 2;
      input({Control.down: 1});
      expect(engine.state.channels['A']!.cursor, 2);
      expect(engine.state.channels['A']!.waveform, 'd6f83af0');
      input({Control.south: 1});
      expect(engine.state.channels['A']!.waveform, 'eea0e4ce');
    },
  );
  test('sequence waveform selection is scoped to the target channel', () {
    configure([
      binding('north', 'waveform', {
        'target': 'B',
        'mode': 'sequence',
        'list': ['d6f83af0', '7eae1e5f', 'eea0e4ce'],
      }),
    ]);
    input({Control.north: 1});
    expect(engine.state.channels['B']!.waveform, '7eae1e5f');
    input({});
    input({Control.north: 1});
    expect(engine.state.channels['B']!.waveform, 'eea0e4ce');
    expect(engine.state.channels['A']!.waveform, 'd6f83af0');
  });
  test('stick accelerates with hold time and stops immediately on neutral', () {
    configure([
      binding('leftStickVector', 'stickStrength', {'target': 'A'}),
    ]);
    input({Control.leftY: -1});
    engine.tick(Duration.zero);
    for (var i = 1; i <= 10; i++) {
      engine.tick(Duration(milliseconds: i * 50));
    }
    final early = engine.state.channels['A']!.base;
    for (var i = 11; i <= 20; i++) {
      engine.tick(Duration(milliseconds: i * 50));
    }
    final later = engine.state.channels['A']!.base - early;
    expect(later, greaterThan(early));
    input({});
    final resting = engine.state.channels['A']!.base;
    engine.tick(const Duration(seconds: 2));
    expect(engine.state.channels['A']!.base, resting);
  });
  test('stick maps to the open touch surface and releases at center', () {
    configure([
      binding('rightStickVector', 'stickCursor', {'target': 'A'}),
    ]);
    engine.state
      ..touchMode = true
      ..touchSurfaceVisible = true
      ..touchChannel = 'A';

    engine.tick(Duration.zero);
    input({Control.rightX: 0.5});
    engine.tick(const Duration(milliseconds: 50));
    expect(engine.state.touchPoint!.x, closeTo(0.75, 0.0001));
    expect(engine.state.touchPoint!.y, closeTo(0.5, 0.0001));
    expect(engine.state.touchPoint!.active, isTrue);

    const diagonal = 0.7071067811865476;
    input({Control.rightX: diagonal, Control.rightY: -diagonal});
    engine.tick(const Duration(milliseconds: 100));
    expect(engine.state.touchPoint!.x, closeTo(1, 0.0001));
    expect(engine.state.touchPoint!.y, closeTo(0, 0.0001));
    expect(engine.state.touchReadout('A'), isNotNull);

    input({});
    engine.tick(const Duration(milliseconds: 150));
    expect(engine.state.touchPoint!.active, isFalse);
    expect(engine.state.touchReadout('A'), isNull);
  });
  test(
    'disconnect clears temporary output and stops channels but retains base',
    () {
      configure([
        binding('leftShoulder', 'boost', {'amount': 30, 'mode': 'toggle'}),
      ]);
      engine.state.channels['A']!
        ..base = 80
        ..enabled = true;
      input({Control.leftShoulder: 1});
      engine.input(GamepadState.neutral, live: false, deviceId: null);
      expect(engine.state.overlays, isEmpty);
      expect(engine.state.channels['A']!.base, 80);
      expect(engine.state.frame().channels['A']!['intensity'], 0);
    },
  );
  test('invalid command batch is atomic', () {
    final state = ControlState();
    expect(
      () => state.apply('bad', [
        {'type': 'setBase', 'channel': 'A', 'value': 80},
        {'type': 'waveform', 'channel': 'B', 'id': 'missing'},
      ]),
      throwsFormatException,
    );
    expect(state.channels['A']!.base, 0);
    expect(
      () => state.apply('bad', [
        {
          'type': 'offset',
          'channel': 'A',
          'unit': 'absolute',
          'value': double.nan,
        },
      ]),
      throwsFormatException,
    );
    final touchState = ControlState()
      ..touchMode = true
      ..touchSurfaceVisible = true
      ..touchChannel = 'A';
    expect(
      () => touchState.apply('rightStick', [
        {'type': 'touchPoint', 'x': 1.2, 'y': 0.5, 'active': true},
      ]),
      throwsFormatException,
    );
    expect(touchState.touchPoint, isNull);
  });
  test('rebinding releases a script-held touch point', () {
    configure([
      binding('rightStickVector', 'stickCursor', {'target': 'A'}),
    ]);
    engine.state
      ..touchMode = true
      ..touchSurfaceVisible = true
      ..touchChannel = 'A';
    engine.tick(Duration.zero);
    input({Control.rightX: 1});
    engine.tick(const Duration(milliseconds: 50));
    expect(engine.state.touchPoint!.active, isTrue);

    engine.configure([], definitions);
    expect(engine.state.touchPoint, isNull);
  });
  test('user script registers metadata and runs through same host', () {
    final runtime = ActionRuntime(
      File('assets/scripts/example.js').readAsStringSync(),
    );
    final def = runtime.definition;
    runtime.dispose();
    definitions[def.id] = def;
    configure([
      Binding(
        id: 'custom',
        input: 'south',
        action: def.id,
        config: def.defaults,
      ),
    ]);
    input({Control.south: 1});
    expect(engine.state.channels['A']!.base, 5);
  });
  test('user stick script can drive the same touch command', () {
    final runtime = ActionRuntime(
      "registerAction({apiVersion:1,id:'user.touch',name:'Touch',inputs:['stick'],fields:[],onEvent(ctx){return ctx.touch.open&&ctx.touch.surface&&ctx.event.type==='tick'?[{type:'touchPoint',x:0.25,y:0.75,active:true}]:[];}});",
    );
    final def = runtime.definition;
    runtime.dispose();
    definitions[def.id] = def;
    configure([
      Binding(
        id: 'touch',
        input: 'leftStickVector',
        action: def.id,
        config: def.defaults,
      ),
    ]);
    engine.state
      ..touchMode = true
      ..touchSurfaceVisible = true
      ..touchChannel = 'A';
    engine.tick(Duration.zero);
    engine.tick(const Duration(milliseconds: 50));
    expect(engine.state.touchPoint!.x, 0.25);
    expect(engine.state.touchPoint!.y, 0.75);
    expect(engine.state.touchPoint!.active, isTrue);
  });
  test(
    'infinite loop is interrupted by native engine and binding is disabled',
    () {
      final source =
          "registerAction({apiVersion:1,id:'user.loop',name:'Loop',inputs:['button'],fields:[],onEvent(){while(true){} }});";
      final runtime = ActionRuntime(source);
      final def = runtime.definition;
      runtime.dispose();
      definitions[def.id] = def;
      configure([Binding(id: 'bad', input: 'south', action: def.id)]);
      final time = Stopwatch()..start();
      input({Control.south: 1});
      expect(time.elapsedMilliseconds, lessThan(1000));
      expect(engine.errors, contains('bad'));
    },
  );
  test('infinite top-level import is interrupted', () {
    final time = Stopwatch()..start();
    expect(() => ActionRuntime('while(true){}'), throwsFormatException);
    expect(time.elapsedMilliseconds, lessThan(1000));
  });
  test('scripts have no native messaging, timers, or network API', () {
    final runtime = ActionRuntime(
      "registerAction({apiVersion:1,id:'user.restricted',name:'Restricted',inputs:['button'],fields:[],onEvent(){if(typeof sendMessage!=='undefined'||typeof fetch!=='undefined'||typeof setTimeout!=='undefined')throw Error('leak');return [];}});",
    );
    expect(runtime.invoke({}), isEmpty);
    runtime.dispose();
  });
  test('memory exhaustion is rejected by the native heap limit', () {
    final runtime = ActionRuntime(
      "registerAction({apiVersion:1,id:'user.memory',name:'Memory',inputs:['button'],fields:[],onEvent(){return [new ArrayBuffer(32*1024*1024)];}});",
    );
    expect(() => runtime.invoke({}), throwsFormatException);
    runtime.dispose();
  });
  test(
    'script fault cancels every gesture and prevents later bindings in that event',
    () {
      final runtime = ActionRuntime(
        "registerAction({apiVersion:1,id:'user.bad',name:'Bad',inputs:['button'],fields:[],onEvent(ctx){if(ctx.event.type==='press')throw Error('fault');return [];}});",
      );
      final def = runtime.definition;
      runtime.dispose();
      definitions[def.id] = def;
      configure([
        binding('leftShoulder', 'boost', {'target': 'A', 'mode': 'toggle'}),
        Binding(id: 'bad', input: 'south', action: def.id),
        binding('rightShoulder', 'toggle', {'target': 'A'}),
      ]);
      input({Control.leftShoulder: 1});
      expect(engine.state.offset('A'), 30);
      input({Control.south: 1, Control.rightShoulder: 1});
      expect(engine.state.overlays, isEmpty);
      expect(engine.state.enabled('A'), isFalse);
      input({});
      input({Control.leftShoulder: 1});
      expect(engine.state.offset('A'), 30);
    },
  );
  test('stop retains base and held controls cannot immediately rearm', () {
    configure([
      binding('leftShoulder', 'boost', {'target': 'A'}),
    ]);
    engine.state.channels['A']!
      ..base = 80
      ..enabled = true;
    input({Control.leftShoulder: 1});
    engine.stopAll();
    input({Control.leftShoulder: 1});
    expect(engine.state.overlays, isEmpty);
    expect(engine.state.channels['A']!.base, 80);
    expect(engine.state.frame().channels['A']!['intensity'], 0);
    input({});
    input({Control.leftShoulder: 1});
    expect(engine.state.offset('A'), 30);
    expect(engine.state.enabled('A'), isFalse);
  });
}
