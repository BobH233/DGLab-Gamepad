import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gamepad_core/gamepad_core.dart';
import '../coyote/coyote_controller.dart';
import '../input/input_monitor.dart';
import '../scripting/action_runtime.dart';
import 'control_engine.dart';
import 'control_state.dart';
import 'control_store.dart';
import 'models.dart';
import 'output_waveform_trace.dart';
import 'pulse_import.dart';

class ControlDesk extends ChangeNotifier {
  final InputMonitor monitor;
  final CoyoteController coyote;
  late final OutputWaveformTrace waveformTrace;
  final PreviewOutputSink output = PreviewOutputSink();
  late final ControlEngine engine = ControlEngine(
    output: _ControlOutput(output, coyote),
  );
  final Map<String, ActionDefinition> actions = {};
  List<Binding> bindings = [];
  List<Waveform> customWaveforms = [];
  final Stopwatch clock = Stopwatch()..start();
  StreamSubscription<dynamic>? _subscription;
  Timer? _timer;
  Timer? _saveTimer;
  Timer? _touchNotifyTimer;
  String _savedChannelKey = '';
  String get _channelKey => engine.state.channels.values
      .map(
        (c) =>
            '${c.base}:${c.waveform}:${c.linearAmount}:${c.linearUnit}:${c.boostAmount}',
      )
      .join('|');
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
    waveformTrace = OutputWaveformTrace(clock: this.coyote.pulseClock);
    this.coyote.addListener(_notify);
    this.coyote.onUnexpectedDisconnect = _handleCoyoteLost;
  }

  void _handleCoyoteLost() {
    if (_disposed) return;
    engine.stopAll();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({ControlStore? storage, AssetBundle? assets}) async {
    var migratedTouchBinding = false;
    setCustomWaveformCatalog(const []);
    customWaveforms = [];
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
          final restoredWaveforms = <Waveform>[];
          final waveformIds = <String>{};
          var totalFrames = 0;
          for (final item in (saved['customWaveforms'] as List? ?? []).take(
            32,
          )) {
            try {
              final waveform = Waveform.fromStorage(item);
              if (builtInWaveforms.any((item) => item.id == waveform.id) ||
                  !waveformIds.add(waveform.id)) {
                throw const FormatException('波形 ID 重复');
              }
              totalFrames += waveform.pulseData.length;
              if (totalFrames > 32768) {
                throw const FormatException('自定义波形总长度超出限制');
              }
              restoredWaveforms.add(waveform);
            } catch (e) {
              loadWarnings.add('波形未载入：$e');
            }
          }
          customWaveforms = restoredWaveforms;
          setCustomWaveformCatalog(customWaveforms);
          if (saved['waveformOrder'] case final List<dynamic> order) {
            setWaveformOrder(order.whereType<String>());
          }
          final scriptNames = switch (saved['scriptNames']) {
            final Map<dynamic, dynamic> names => names,
            _ => const <dynamic, dynamic>{},
          };
          for (final source in (saved['scripts'] as List? ?? []).take(32)) {
            try {
              final runtime = ActionRuntime(source as String);
              if (actions.containsKey(runtime.definition.id)) {
                runtime.dispose();
                throw const FormatException('脚本 ID 重复');
              }
              final savedName = scriptNames[runtime.definition.id];
              String? displayName;
              if (savedName is String) {
                try {
                  displayName = _normalizeScriptName(savedName);
                } catch (e) {
                  loadWarnings.add('脚本名称未载入：$e');
                }
              }
              actions[runtime.definition.id] = displayName == null
                  ? runtime.definition
                  : runtime.definition.withDisplayName(displayName);
              runtime.dispose();
            } catch (e) {
              loadWarnings.add('脚本未载入：$e');
            }
          }
          final savedVersion = switch (saved['version']) {
            final num value => value.toInt(),
            _ => 1,
          };
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
              final config = definition.validateConfig(binding.config);
              if (savedVersion < 4) {
                _restoreLegacyControls(binding.action, binding.config);
              }
              restored.add(
                Binding(
                  id: binding.id,
                  input: binding.input,
                  action: binding.action,
                  config: config,
                  enabled: binding.enabled,
                  threshold: binding.threshold,
                ),
              );
            } catch (e) {
              loadWarnings.add('绑定未载入：$e');
            }
          }
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
            final linear = data?['linear'] as Map?;
            final linearAmount = linear?['amount'];
            if (linearAmount is num && linearAmount.isFinite) {
              engine.state.channels[id]!.linearAmount = linearAmount
                  .toDouble()
                  .clamp(-200, 200);
            }
            final linearUnit = linear?['unit'];
            if (linearUnit == 'absolute' || linearUnit == 'percent') {
              engine.state.channels[id]!.linearUnit = linearUnit as String;
            }
            final boost = data?['boost'] as Map?;
            final boostAmount = boost?['amount'];
            if (boostAmount is num && boostAmount.isFinite) {
              engine.state.channels[id]!.boostAmount = boostAmount
                  .toDouble()
                  .clamp(0, 200);
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
        final preserveOutput =
            frame.status == InputStatus.paused && monitor.lifecycleSuspended;
        if (frame.status == InputStatus.error ||
            frame.status == InputStatus.stale ||
            (frame.status == InputStatus.paused && !preserveOutput)) {
          engine.stopAll();
        }
        engine.input(
          frame.state,
          live: !editing && frame.status == InputStatus.live,
          deviceId: frame.deviceId,
          raw: monitor.session.raw,
          preserveOutput: preserveOutput,
        );
        _persistChanges();
        _notify();
      });
      engine.input(
        monitor.session.state,
        live: monitor.session.status == InputStatus.live,
        deviceId: monitor.session.selectedId,
        raw: monitor.session.raw,
      );
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!editing) {
          final before = engine.revision;
          engine.tick(clock.elapsed);
          if (engine.revision != before) {
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
      config: {'target': 'A'},
    ),
    const Binding(
      id: 'rt',
      input: 'rightTrigger',
      action: 'builtin.linear',
      config: {'target': 'B'},
    ),
    const Binding(
      id: 'lb',
      input: 'leftShoulder',
      action: 'builtin.boost',
      config: {'target': 'A', 'mode': 'hold'},
    ),
    const Binding(
      id: 'rb',
      input: 'rightShoulder',
      action: 'builtin.boost',
      config: {'target': 'B', 'mode': 'hold'},
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
        'version': 6,
        'autoScrollToAction': autoScrollToAction,
        'waveformOrder': waveforms.map((waveform) => waveform.id).toList(),
        'bindings': bindings.map((b) => b.toJson()).toList(),
        'customWaveforms': customWaveforms
            .map((waveform) => waveform.toJson())
            .toList(),
        'scripts': actions.values
            .where((a) => !a.builtin)
            .map((a) => a.source)
            .toList(),
        'scriptNames': {
          for (final action in actions.values)
            if (!action.builtin && action.name != action.registeredName)
              action.id: action.name,
        },
        'channels': engine.state.channels.map(
          (k, v) => MapEntry(k, {
            'base': v.base,
            'waveform': v.waveform,
            'linear': {'amount': v.linearAmount, 'unit': v.linearUnit},
            'boost': {'amount': v.boostAmount},
          }),
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

  Future<void> setChannelControls(
    String id, {
    required double linearAmount,
    required String linearUnit,
    required double boostAmount,
  }) async {
    if (!channelIds.contains(id) ||
        !linearAmount.isFinite ||
        linearAmount < -200 ||
        linearAmount > 200 ||
        !['absolute', 'percent'].contains(linearUnit) ||
        !boostAmount.isFinite ||
        boostAmount < 0 ||
        boostAmount > 200) {
      throw ArgumentError('通道控制参数无效');
    }
    final previousLinear = engine.state.channels[id]!.linearAmount;
    final activeActions = {
      for (final binding in bindings) binding.id: binding.action,
    };
    for (final entry in engine.state.overlays.entries.toList()) {
      final overlay = entry.value;
      if (overlay['channel'] != id) continue;
      final action = activeActions[entry.key];
      if (action == 'builtin.boost') {
        engine.state.overlays[entry.key] = Map.unmodifiable({
          ...overlay,
          'unit': 'absolute',
          'value': boostAmount,
        });
      } else if (action == 'builtin.linear') {
        final previousValue = overlay['value'];
        final ratio = previousLinear.abs() > 0.000001 && previousValue is num
            ? previousValue / previousLinear
            : 0.0;
        engine.state.overlays[entry.key] = Map.unmodifiable({
          ...overlay,
          'unit': linearUnit,
          'value': (linearAmount * ratio).clamp(-200, 200),
        });
      }
    }
    engine.state.channels[id]!
      ..linearAmount = linearAmount
      ..linearUnit = linearUnit
      ..boostAmount = boostAmount;
    engine.publish();
    _notify();
    await save();
  }

  void _restoreLegacyControls(String action, Map<String, dynamic> config) {
    final target = config['target'];
    final targets = target == 'selected'
        ? channelIds
        : channelIds.contains(target)
        ? [target as String]
        : const <String>[];
    if (targets.isEmpty) return;
    final amount = config['amount'];
    if (amount is! num || !amount.isFinite) return;
    final unit = config['unit'];
    for (final id in targets) {
      final channel = engine.state.channels[id]!;
      if (action == 'builtin.linear') {
        channel.linearAmount = amount.toDouble().clamp(-200, 200);
        if (unit == 'absolute' || unit == 'percent') {
          channel.linearUnit = unit as String;
        }
      } else if (action == 'builtin.boost') {
        channel.boostAmount = amount.toDouble().clamp(0, 200);
      }
    }
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
    if (index < 0 || index >= waveforms.length) {
      throw RangeError.index(index, waveforms);
    }
    final c = engine.state.channels[engine.state.selected]!;
    c.cursor = index;
    c.waveform = waveforms[index].id;
    engine.publish();
    _notify();
    unawaited(save());
  }

  Future<void> reorderWaveforms(List<String> order) async {
    final ids = waveforms.map((waveform) => waveform.id).toSet();
    if (order.length != ids.length ||
        order.toSet().length != ids.length ||
        !order.every(ids.contains)) {
      throw ArgumentError.value(order, 'order', '波形顺序必须包含全部波形');
    }
    if (listEquals(order, waveforms.map((waveform) => waveform.id).toList())) {
      return;
    }
    final cursors = {
      for (final entry in engine.state.channels.entries)
        entry.key: waveforms[entry.value.cursor].id,
    };
    final focus = engine.state.focusTarget;
    final focusedId = focus?.area == ControlFocusArea.waveform
        ? waveforms[focus!.waveformIndex].id
        : null;
    setWaveformOrder(order);
    for (final entry in cursors.entries) {
      engine.state.channels[entry.key]!.cursor = order.indexOf(entry.value);
    }
    if (focusedId != null) {
      engine.state.focusTarget = (
        area: ControlFocusArea.waveform,
        channel: focus!.channel,
        waveformIndex: order.indexOf(focusedId),
      );
    }
    _notify();
    await save();
  }

  Future<Waveform> importPulseWaveform(
    String source, {
    required String name,
  }) async {
    if (customWaveforms.length >= 32) {
      throw const FormatException('最多导入 32 个自定义波形');
    }
    final parsed = parsePulseWaveform(source, name: name);
    for (final existing in customWaveforms) {
      if (listEquals(existing.pulseData, parsed.pulseData)) {
        _applyWaveform(existing.id);
        await save();
        return existing;
      }
    }
    final baseId = parsed.id;
    var id = baseId;
    var suffix = 2;
    while (waveforms.any((waveform) => waveform.id == id)) {
      id = '$baseId-$suffix';
      suffix++;
    }
    final waveform = Waveform(
      id,
      parsed.name,
      parsed.pulseData,
      isCustom: true,
    );
    final next = [waveform, ...customWaveforms];
    setCustomWaveformCatalog(
      next,
      order: [id, ...waveforms.map((waveform) => waveform.id)],
    );
    customWaveforms = next;
    _applyWaveform(id);
    await save();
    return waveform;
  }

  void _applyWaveform(String id) {
    final channel = engine.state.channels[engine.state.selected]!;
    channel.waveform = id;
    channel.cursor = waveforms.indexWhere((waveform) => waveform.id == id);
    for (final item in engine.state.channels.values) {
      item.cursor = waveforms.indexWhere(
        (waveform) => waveform.id == item.waveform,
      );
    }
    engine.publish();
    _notify();
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

  bool get anyChannelEnabled => channelIds.any(
    (id) =>
        engine.state.enabled(id) ||
        (engine.state.touchReadout(id)?.intensity ?? 0) > 0,
  );

  void startAll() {
    engine.cancel();
    for (final channel in engine.state.channels.values) {
      channel.enabled = true;
    }
    engine.publish();
    coyote.flushLatest();
    _notify();
  }

  void toggleAllChannels() {
    if (anyChannelEnabled) {
      stopAll();
    } else {
      startAll();
    }
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
      raw: monitor.session.raw,
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

  Future<void> renameScript(String id, String value) async {
    final action = actions[id];
    if (action == null || action.builtin) {
      throw const FormatException('只能重命名导入脚本');
    }
    final name = _normalizeScriptName(value);
    if (name == action.name) return;
    actions[id] = action.withDisplayName(name);
    _notify();
    await save();
  }

  static String _normalizeScriptName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 40) {
      throw const FormatException('脚本名称需要 1–40 个字符');
    }
    return name;
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
    coyote.onUnexpectedDisconnect = null;
    coyote.dispose();
    waveformTrace.dispose();
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
