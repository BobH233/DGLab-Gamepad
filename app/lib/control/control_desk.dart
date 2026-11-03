import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gamepad_core/gamepad_core.dart';
import '../coyote/coyote_controller.dart';
import '../input/input_monitor.dart';
import '../scripting/action_runtime.dart';
import 'control_engine.dart';
import 'control_store.dart';
import 'models.dart';

class ControlDesk extends ChangeNotifier {
  final InputMonitor monitor;
  final CoyoteController coyote;
  final PreviewOutputSink output = PreviewOutputSink();
  late final ControlEngine engine = ControlEngine(
    output: _ControlOutput(output, coyote),
  );
  final Map<String, ActionDefinition> actions = {};
  List<Binding> bindings = [];
  final Stopwatch clock = Stopwatch()..start();
  StreamSubscription<dynamic>? _subscription;
  Timer? _timer;
  Timer? _saveTimer;
  Timer? _touchNotifyTimer;
  String _savedChannelKey = '';
  String get _channelKey => engine.state.channels.values
      .map((c) => '${c.base}:${c.waveform}')
      .join('|');
  String get _viewKey {
    final state = engine.state;
    return [
      state.selected,
      state.columns,
      state.touchMode,
      state.touchChannel,
      state.touchPoint?.x,
      state.touchPoint?.y,
      state.touchPoint?.active,
      state.touchGrid,
      state.touchPanelRequest,
      state.touchPanelRequestChannel,
      for (final id in channelIds) state.touchBalance[id],
      for (final id in channelIds) state.touchHorizontalSplits[id]?.join(':'),
      for (final id in channelIds) state.touchVerticalSplits[id]?.join(':'),
      for (final id in channelIds)
        [
          state.channels[id]!.base,
          state.enabled(id),
          state.channels[id]!.waveform,
          state.channels[id]!.cursor,
          state.effective(id),
          state.offset(id),
        ].join(':'),
      for (final entry in engine.errors.entries) '${entry.key}:${entry.value}',
    ].join('|');
  }

  void _persistChanges() {
    if (_channelKey == _savedChannelKey || _saveTimer != null) return;
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      _saveTimer = null;
      unawaited(save());
    });
  }

  ControlStore? store;
  bool ready = false;
  bool autoScrollToAction = true;
  bool _disposed = false;
  String? error;
  String? persistenceError;
  final List<String> loadWarnings = [];
  ControlDesk(this.monitor, {CoyoteController? coyote})
    : coyote = coyote ?? CoyoteController() {
    this.coyote.addListener(_notify);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({ControlStore? storage, AssetBundle? assets}) async {
    var migratedTouchBinding = false;
    try {
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
        'toggle_touch',
      ]) {
        final source = await (assets ?? rootBundle).loadString(
          'assets/actions/$name.js',
        );
        if (_disposed) return;
        final runtime = ActionRuntime(source, builtin: true);
        actions[runtime.definition.id] = runtime.definition;
        runtime.dispose();
      }
      bindings = defaultBindings();
      try {
        store = storage ?? await ControlStore.open();
        if (_disposed) return;
        final saved = await store!.read();
        if (_disposed) return;
        if (saved != null) {
          for (final source in (saved['scripts'] as List? ?? []).take(32)) {
            try {
              final runtime = ActionRuntime(source as String);
              if (actions.containsKey(runtime.definition.id)) {
                runtime.dispose();
                throw const FormatException('脚本 ID 重复');
              }
              actions[runtime.definition.id] = runtime.definition;
              runtime.dispose();
            } catch (e) {
              loadWarnings.add('脚本未载入：$e');
            }
          }
          final restored = <Binding>[];
          for (final item in saved['bindings'] as List? ?? []) {
            try {
              final binding = Binding.fromJson(
                Map<String, dynamic>.from(item as Map),
              );
              if (!actions.containsKey(binding.action)) {
                throw const FormatException('操作缺失');
              }
              final definition = actions[binding.action]!;
              final kind = inputKind(binding.input);
              if (!inputLabels.containsKey(binding.input) ||
                  (!definition.inputs.contains(kind) &&
                      !(kind == 'trigger' &&
                          definition.inputs.contains('button'))) ||
                  !binding.threshold.isFinite ||
                  restored.length >= 24 ||
                  restored.any(
                    (b) => b.id == binding.id || b.input == binding.input,
                  )) {
                throw const FormatException('绑定输入无效或重复');
              }
              definition.validateConfig(binding.config);
              restored.add(binding);
            } catch (e) {
              loadWarnings.add('绑定未载入：$e');
            }
          }
          final savedVersion = switch (saved['version']) {
            final num value => value.toInt(),
            _ => 1,
          };
          if (saved['autoScrollToAction'] case final bool value) {
            autoScrollToAction = value;
          }
          if (savedVersion < 2 &&
              !restored.any((binding) => binding.input == 'north') &&
              actions.containsKey('builtin.toggleTouch')) {
            restored.add(
              const Binding(
                id: 'north_touch',
                input: 'north',
                action: 'builtin.toggleTouch',
              ),
            );
            migratedTouchBinding = true;
          }
          bindings = restored;
          for (final id in channelIds) {
            final data = (saved['channels'] as Map?)?[id] as Map?;
            final base = data?['base'];
            if (base is num && base.isFinite) {
              engine.state.channels[id]!.base = base.toDouble().clamp(0, 200);
            }
            final wave = canonicalWaveformId(data?['waveform']);
            if (waveforms.any((w) => w.id == wave)) {
              engine.state.channels[id]!.waveform = wave;
              engine.state.channels[id]!.cursor = waveforms.indexWhere(
                (w) => w.id == wave,
              );
            }
          }
          final touch = saved['touch'] as Map?;
          if (touch != null) {
            engine.state.touchGrid = touch['grid'] as bool? ?? true;
            final balance = touch['balance'] as Map?;
            for (final id in channelIds) {
              final value = balance?[id];
              if (value is num && value.isFinite) {
                engine.state.touchBalance[id] = value.toDouble().clamp(0, 1);
              }
            }
            final horizontal = touch['horizontal'] as Map?;
            final vertical = touch['vertical'] as Map?;
            for (final id in channelIds) {
              _restoreSplits(
                engine.state.touchHorizontalSplits,
                id,
                horizontal,
              );
              _restoreSplits(engine.state.touchVerticalSplits, id, vertical);
            }
          }
        }
      } catch (e) {
        persistenceError = '读取配置失败：$e';
      }
      if (_disposed) return;
      engine.configure(bindings, actions);
      _savedChannelKey = _channelKey;
      _subscription = monitor.frames.listen((frame) {
        if (frame.status == InputStatus.paused ||
            frame.status == InputStatus.error ||
            frame.status == InputStatus.stale) {
          engine.stopAll();
        }
        engine.input(
          frame.state,
          live: !editing && frame.status == InputStatus.live,
          deviceId: frame.deviceId,
        );
        _persistChanges();
        _notify();
      });
      engine.input(
        monitor.session.state,
        live: monitor.session.status == InputStatus.live,
        deviceId: monitor.session.selectedId,
      );
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!editing) {
          final before = _viewKey;
          engine.tick(clock.elapsed);
          if (_viewKey != before) {
            _persistChanges();
            _notify();
          }
        }
      });
      ready = true;
      if (migratedTouchBinding) await save();
    } catch (e) {
      error = '控制台初始化失败：$e';
    }
    _notify();
  }

  static List<Binding> defaultBindings() => [
    const Binding(
      id: 'lt',
      input: 'leftTrigger',
      action: 'builtin.linear',
      config: {'target': 'A', 'unit': 'absolute', 'amount': 30},
    ),
    const Binding(
      id: 'rt',
      input: 'rightTrigger',
      action: 'builtin.linear',
      config: {'target': 'B', 'unit': 'absolute', 'amount': 30},
    ),
    const Binding(
      id: 'lb',
      input: 'leftShoulder',
      action: 'builtin.boost',
      config: {'target': 'A', 'amount': 30, 'mode': 'hold'},
    ),
    const Binding(
      id: 'rb',
      input: 'rightShoulder',
      action: 'builtin.boost',
      config: {'target': 'B', 'amount': 30, 'mode': 'hold'},
    ),
    const Binding(
      id: 'select',
      input: 'view',
      action: 'builtin.select',
      config: {'channel': 'toggle'},
    ),
    const Binding(
      id: 'start',
      input: 'menu',
      action: 'builtin.toggle',
      config: {'target': 'selected', 'mode': 'toggle'},
    ),
    const Binding(
      id: 'confirm',
      input: 'south',
      action: 'builtin.confirm',
      config: {'target': 'selected'},
    ),
    const Binding(
      id: 'north_touch',
      input: 'north',
      action: 'builtin.toggleTouch',
    ),
    const Binding(
      id: 'ls',
      input: 'leftStickVector',
      action: 'builtin.stickStrength',
      config: {'target': 'selected'},
    ),
    const Binding(
      id: 'rs',
      input: 'rightStickVector',
      action: 'builtin.stickCursor',
      config: {'target': 'selected'},
    ),
    for (final direction in ['up', 'down', 'left', 'right'])
      Binding(
        id: 'dpad_$direction',
        input: direction,
        action: 'builtin.navigate',
        config: {'target': 'selected', 'direction': direction},
      ),
  ];
  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final channelKey = _channelKey;
    try {
      await store?.save({
        'version': 3,
        'autoScrollToAction': autoScrollToAction,
        'bindings': bindings.map((b) => b.toJson()).toList(),
        'scripts': actions.values
            .where((a) => !a.builtin)
            .map((a) => a.source)
            .toList(),
        'channels': engine.state.channels.map(
          (k, v) => MapEntry(k, {'base': v.base, 'waveform': v.waveform}),
        ),
        'touch': {
          'grid': engine.state.touchGrid,
          'balance': engine.state.touchBalance,
          'horizontal': engine.state.touchHorizontalSplits,
          'vertical': engine.state.touchVerticalSplits,
        },
      });
      persistenceError = store == null ? '本地存储不可用' : null;
      _savedChannelKey = channelKey;
    } catch (e) {
      persistenceError = '保存失败：$e';
    }
    _notify();
  }

  void selectChannel(String id) {
    engine.state.selected = id;
    if (engine.state.touchMode) {
      engine.state
        ..touchChannel = id
        ..clearTouchPoint();
    }
    engine.publish();
    _notify();
  }

  void setAutoScrollToAction(bool value) {
    if (autoScrollToAction == value) return;
    autoScrollToAction = value;
    _notify();
    unawaited(save());
  }

  void setBase(String id, double value, {bool persist = true}) {
    engine.state.channels[id]!.base = value.clamp(0, 200);
    engine.publish();
    _notify();
    if (persist) unawaited(save());
  }

  void toggle(String id) {
    final c = engine.state.channels[id]!;
    c.enabled = !c.enabled;
    engine.publish();
    _notify();
  }

  bool get touchOpen => engine.state.touchMode;
  String get touchChannel => engine.state.touchChannel;

  void openTouchChannel(String id) {
    if (!channelIds.contains(id)) return;
    engine.state
      ..touchMode = true
      ..touchSurfaceVisible = true
      ..touchChannel = id
      ..selected = id
      ..clearTouchPoint();
    engine.publish();
    coyote.flushLatest();
    _notify();
  }

  void closeTouchPanel() {
    _touchNotifyTimer?.cancel();
    _touchNotifyTimer = null;
    engine.state
      ..touchMode = false
      ..touchSurfaceVisible = false
      ..clearTouchPoint();
    engine.publish();
    coyote.flushLatest();
    _notify();
  }

  void setTouchSurfaceVisible(bool visible) {
    if (!engine.state.touchMode ||
        engine.state.touchSurfaceVisible == visible) {
      return;
    }
    engine.state.touchSurfaceVisible = visible;
    if (!visible) {
      engine.state.clearTouchPoint();
      engine.publish();
      coyote.flushLatest();
      _notify();
      return;
    }
    engine.publish();
    _notify();
  }

  void updateTouchPoint(double x, double y, {bool notify = false}) {
    if (!engine.state.touchMode || !engine.state.touchSurfaceVisible) return;
    engine.state.beginScreenTouch(x, y);
    engine.publish();
    if (notify) {
      _notify();
    } else {
      _touchNotifyTimer ??= Timer(const Duration(milliseconds: 33), () {
        _touchNotifyTimer = null;
        _notify();
      });
    }
  }

  void endTouchPoint() {
    _touchNotifyTimer?.cancel();
    _touchNotifyTimer = null;
    final point = engine.state.touchPoint;
    if (point == null || !point.active) return;
    engine.state.endScreenTouch();
    engine.publish();
    coyote.flushLatest();
    _notify();
  }

  void setTouchGrid(bool value) {
    if (engine.state.touchGrid == value) return;
    engine.state.touchGrid = value;
    unawaited(save());
    _notify();
  }

  void setTouchBalance(String id, double value, {bool persist = true}) {
    if (!channelIds.contains(id)) return;
    engine.state.touchBalance[id] = value.clamp(0, 1);
    engine.publish();
    _notify();
    if (persist) unawaited(save());
  }

  void setTouchHorizontalSplits(
    String id,
    double first,
    double second, {
    bool persist = true,
  }) {
    _setTouchSplits(
      engine.state.touchHorizontalSplits,
      id,
      first,
      second,
      persist: persist,
    );
  }

  void setTouchVerticalSplits(
    String id,
    double first,
    double second, {
    bool persist = true,
  }) {
    _setTouchSplits(
      engine.state.touchVerticalSplits,
      id,
      first,
      second,
      persist: persist,
    );
  }

  void _setTouchSplits(
    Map<String, List<double>> target,
    String id,
    double first,
    double second, {
    required bool persist,
  }) {
    if (!channelIds.contains(id)) return;
    final a = first.clamp(0.12, 0.76);
    final b = second.clamp(a + 0.12, 0.88);
    target[id] = [a, b];
    engine.publish();
    _notify();
    if (persist) unawaited(save());
  }

  void _restoreSplits(
    Map<String, List<double>> target,
    String id,
    Map? source,
  ) {
    final value = source?[id];
    if (value is! List || value.length != 2) return;
    final first = value[0];
    final second = value[1];
    if (first is! num ||
        second is! num ||
        !first.isFinite ||
        !second.isFinite) {
      return;
    }
    final a = first.toDouble().clamp(0.12, 0.76);
    final b = second.toDouble().clamp(a + 0.12, 0.88);
    target[id] = [a, b];
  }

  void chooseWaveform(int index) {
    final c = engine.state.channels[engine.state.selected]!;
    c.cursor = index;
    c.waveform = waveforms[index].id;
    engine.publish();
    _notify();
    unawaited(save());
  }

  void focusWaveform(int index) {
    engine.state.channels[engine.state.selected]!.cursor = index;
    _notify();
  }

  void stopAll() {
    engine.stopAll();
    unawaited(coyote.emergencyStop());
    _notify();
  }

  void suspendBindings() {
    engine.cancel();
    _notify();
  }

  void resumeBindings() {
    engine.input(
      monitor.session.state,
      live: monitor.session.status == InputStatus.live,
      deviceId: monitor.session.selectedId,
    );
  }

  bool editing = false;
  void beginEdit() {
    editing = true;
    engine.stopAll();
    unawaited(coyote.emergencyStop());
    _notify();
  }

  void endEdit() {
    editing = false;
    engine.cancel();
    _notify();
  }

  Future<void> setBinding(Binding binding) async {
    final next = [...bindings.where((b) => b.input != binding.input), binding];
    engine.configure(next, actions);
    bindings = next;
    _notify();
    await save();
  }

  Future<void> removeBinding(String id) async {
    final next = bindings.where((b) => b.id != id).toList();
    engine.configure(next, actions);
    bindings = next;
    _notify();
    await save();
  }

  Future<void> resetBindings() async {
    final next = defaultBindings();
    engine.configure(next, actions);
    bindings = next;
    _notify();
    await save();
  }

  ActionDefinition validateScript(String source) {
    if (actions.values.where((a) => !a.builtin).length >= 32) {
      throw const FormatException('最多导入 32 个脚本');
    }
    final runtime = ActionRuntime(source);
    final definition = runtime.definition;
    runtime.dispose();
    if (actions.containsKey(definition.id)) {
      throw const FormatException('操作 ID 已存在，请换一个 ID');
    }
    return definition;
  }

  Future<void> install(ActionDefinition definition) async {
    if (actions.containsKey(definition.id)) {
      throw const FormatException('操作 ID 已存在');
    }
    actions[definition.id] = definition;
    await save();
    _notify();
  }

  Future<void> uninstall(String id) async {
    if (actions[id]?.builtin != false) return;
    final next = bindings.where((b) => b.action != id).toList();
    engine.configure(next, actions);
    bindings = next;
    actions.remove(id);
    await save();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _saveTimer?.cancel();
    _touchNotifyTimer?.cancel();
    if (ready && _channelKey != _savedChannelKey) unawaited(save());
    _subscription?.cancel();
    coyote.removeListener(_notify);
    coyote.dispose();
    engine.dispose();
    super.dispose();
  }
}

class _ControlOutput implements OutputSink {
  final PreviewOutputSink preview;
  final CoyoteController coyote;
  _ControlOutput(this.preview, this.coyote);

  @override
  void accept(OutputFrame frame) {
    preview.accept(frame);
    coyote.accept(frame);
  }
}
