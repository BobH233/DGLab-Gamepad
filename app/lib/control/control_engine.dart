import 'dart:math' as math;
import 'package:gamepad_core/gamepad_core.dart';
import '../scripting/action_runtime.dart';
import 'control_state.dart';
import 'models.dart';

class _Slot {
  final Binding binding;
  final ActionRuntime runtime;
  bool pressed = false;
  double previousValue = 0;
  _Slot(this.binding, this.runtime);
}

class ControlEngine {
  final ControlState state = ControlState();
  final OutputSink output;
  final math.Random _random;
  final Map<String, _Slot> _slots = {};
  final Map<String, String> errors = {};
  final List<String> eventLog = [];
  GamepadState _input = GamepadState.neutral;
  bool _live = false;
  String? _deviceId;
  Duration? _lastTick;
  ControlEngine({required this.output, math.Random? random})
    : _random = random ?? math.Random();

  void configure(
    List<Binding> bindings,
    Map<String, ActionDefinition> definitions,
  ) {
    final next = <String, _Slot>{};
    if (bindings.length > 24) throw const FormatException('最多允许 24 个绑定');
    try {
      for (final binding in bindings.where((b) => b.enabled)) {
        if (!binding.threshold.isFinite ||
            binding.threshold < 0.15 ||
            binding.threshold > 0.95) {
          throw const FormatException('触发阈值超出范围');
        }
        final definition = definitions[binding.action];
        if (definition == null) {
          throw FormatException('找不到操作 ${binding.action}');
        }
        if (!inputLabels.containsKey(binding.input)) {
          throw const FormatException('未知输入');
        }
        final kind = inputKind(binding.input);
        if (!definition.inputs.contains(kind) &&
            !(kind == 'trigger' && definition.inputs.contains('button'))) {
          throw const FormatException('操作不支持该输入');
        }
        definition.validateConfig(binding.config);
        if (next.containsKey(binding.id) ||
            next.values.any((s) => s.binding.input == binding.input)) {
          throw const FormatException('同一输入只能绑定一个操作');
        }
        next[binding.id] = _Slot(
          binding,
          ActionRuntime(definition.source, builtin: definition.builtin),
        );
      }
    } catch (_) {
      for (final slot in next.values) {
        slot.runtime.dispose();
      }
      rethrow;
    }
    cancel();
    for (final slot in _slots.values) {
      slot.runtime.dispose();
    }
    _slots
      ..clear()
      ..addAll(next);
    errors.clear();
    _live = false;
  }

  void input(
    GamepadState value, {
    required bool live,
    required String? deviceId,
  }) {
    if (!live || (_deviceId != null && deviceId != _deviceId)) {
      if (_live || state.overlays.isNotEmpty) stopAll();
      _live = false;
    }
    _deviceId = deviceId;
    if (!live) {
      _input = GamepadState.neutral;
      publish();
      return;
    }
    if (!_live) {
      if (!value.isNeutral) {
        publish();
        return;
      }
      _live = true;
    }
    _input = value;
    for (final slot in _slots.values.toList()) {
      if (!_live) break;
      if (errors.containsKey(slot.binding.id)) continue;
      final kind = inputKind(slot.binding.input);
      if (kind == 'stick') continue;
      final control = Control.values.byName(slot.binding.input);
      final current = value[control];
      if (kind == 'trigger' &&
          slot.runtime.definition.inputs.contains('trigger')) {
        if ((current - slot.previousValue).abs() > 0.0001) {
          _invoke(slot, {'type': 'value', 'value': current});
        }
      } else {
        final threshold = kind == 'trigger' ? slot.binding.threshold : 0.5;
        final pressed = slot.pressed
            ? current > threshold - 0.1
            : current >= threshold;
        if (pressed != slot.pressed) {
          slot.pressed = pressed;
          _invoke(slot, {
            'type': pressed ? 'press' : 'release',
            'value': current,
          });
        }
      }
      slot.previousValue = current;
    }
    publish();
  }

  void tick(Duration now) {
    final previous = _lastTick;
    _lastTick = now;
    if (!_live || previous == null) return;
    final dt = ((now - previous).inMicroseconds / 1000000).clamp(0.0, 0.1);
    for (final slot in _slots.values.toList()) {
      if (!_live) break;
      if (errors.containsKey(slot.binding.id)) continue;
      _invoke(slot, {'type': 'tick', 'dt': dt});
    }
    publish();
  }

  void _invoke(_Slot slot, Map<String, dynamic> event) {
    try {
      final binding = slot.binding;
      final isLeft = binding.input == 'leftStickVector';
      final config = slot.runtime.definition.validateConfig(binding.config);
      final target = config['target'] == 'A' || config['target'] == 'B'
          ? config['target']
          : state.selected;
      final commands = slot.runtime.invoke({
        'apiVersion': 1,
        'bindingId': binding.id,
        'event': event,
        'config': config,
        'target': target,
        'selected': state.selected,
        'channels': state.context(),
        'touch': state.touchContext(),
        'input': inputKind(binding.input) == 'stick'
            ? {
                'x': _input[isLeft ? Control.leftX : Control.rightX],
                'y': _input[isLeft ? Control.leftY : Control.rightY],
              }
            : {'value': _input[Control.values.byName(binding.input)]},
        'waveforms': waveforms
            .map((w) => {'id': w.id, 'name': w.name})
            .toList(),
        'grid': {'columns': state.columns, 'count': waveforms.length},
        'random': _random.nextDouble(),
      });
      state.apply(binding.id, commands);
      if (commands.isNotEmpty &&
          event['type'] != 'tick' &&
          event['type'] != 'value') {
        eventLog.insert(
          0,
          '${inputLabels[binding.input]} · ${slot.runtime.definition.name}',
        );
        if (eventLog.length > 40) eventLog.removeLast();
      }
    } catch (e) {
      errors[slot.binding.id] = e.toString();
      stopAll();
    }
  }

  void cancel() {
    state.overlays.clear();
    state.clearTouchPoint();
    for (final slot in _slots.values) {
      slot.pressed = false;
      slot.previousValue = 0;
      try {
        slot.runtime.reset();
      } catch (e) {
        errors[slot.binding.id] = e.toString();
      }
    }
    _input = GamepadState.neutral;
    _live = false;
    _lastTick = null;
    publish();
  }

  void stopAll() {
    cancel();
    state.stop();
    publish();
  }

  void publish() => output.accept(state.frame());
  void dispose() {
    for (final s in _slots.values) {
      s.runtime.dispose();
    }
    _slots.clear();
  }
}
