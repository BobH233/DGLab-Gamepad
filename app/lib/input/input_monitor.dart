import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:gamepad_bridge/gamepad_bridge.dart';
import 'package:gamepad_core/gamepad_core.dart';

class InputMonitor extends ChangeNotifier with WidgetsBindingObserver {
  final InputSession session = InputSession();
  final _frames =
      StreamController<
        ({GamepadState state, InputStatus status, String? deviceId})
      >.broadcast(sync: true);
  Stream<({GamepadState state, InputStatus status, String? deviceId})>
  get frames => _frames.stream;
  void _emitInput() {
    if (!_disposed) {
      _frames.add((
        state: session.state,
        status: session.status,
        deviceId: session.selectedId,
      ));
    }
  }

  final Stopwatch _clock = Stopwatch()..start();
  final List<Map<String, dynamic>> history = [];
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _watchdog;
  bool _paused = false;
  bool _foreground = true;
  bool _disposed = false;
  bool _notificationPending = false;
  String? error;
  int changes = 0;
  int _lastChanges = 0;
  int updatesPerSecond = 0;
  Duration _rateTime = Duration.zero;
  bool get paused => _paused;

  InputMonitor({
    Stream<Map<String, dynamic>>? events,
    bool observeLifecycle = true,
  }) {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _subscription = (events ?? GamepadBridge().events).listen(
      _accept,
      onError: (Object e) => _fail(e.toString()),
      onDone: () => _fail('输入连接已关闭'),
    );
    _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final before = session.status;
      session.checkTimeout(_clock.elapsed);
      if (before != session.status) _emitInput();
      if (_clock.elapsed - _rateTime >= const Duration(seconds: 1)) {
        updatesPerSecond = changes - _lastChanges;
        _lastChanges = changes;
        _rateTime = _clock.elapsed;
        _refresh();
      } else if (before != session.status) {
        _refresh();
      }
    });
  }

  void _accept(Map<String, dynamic> event) {
    try {
      final previous = session.raw;
      final previousId = session.selectedId;
      session.accept(event, _clock.elapsed);
      _emitInput();
      error = null;
      final changed = <String, double>{};
      for (final control in Control.values) {
        final value = session.raw[control];
        if ((value - previous[control]).abs() > 0.0001) {
          changed[control.name] = value;
        }
      }
      if (changed.isNotEmpty || previousId != session.selectedId) {
        changes++;
        history.insert(0, {
          'timeMs': _clock.elapsedMilliseconds,
          'deviceId': session.selectedId,
          'values': changed,
        });
        if (history.length > 80) history.removeLast();
      }
      _refresh();
    } catch (e) {
      _fail('输入数据格式异常：$e');
    }
  }

  void _fail(String message) {
    error = message;
    session.invalidate();
    _emitInput();
    _refresh();
  }

  void _refresh() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  void select(String id) {
    session.select(id);
    _emitInput();
    _refresh();
  }

  void setDeadZone(double value) {
    session.setDeadZone(value);
    _emitInput();
    _refresh();
  }

  void togglePause() {
    _paused = !_paused;
    session.setEnabled(!_paused && _foreground);
    _emitInput();
    _refresh();
  }

  void clearHistory() {
    history.clear();
    changes = 0;
    _lastChanges = 0;
    updatesPerSecond = 0;
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    session.setEnabled(!_paused && _foreground);
    _emitInput();
    _refresh();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'status': session.status.name,
    'deadZone': session.normalizer.deadZone,
    'selectedId': session.selectedId,
    'devices': session.devices.values.map((d) => d.metadata).toList(),
    'raw': session.raw.toJson(),
    'normalized': session.state.toJson(),
    'events': history.reversed.toList(),
  });

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _watchdog?.cancel();
    _subscription?.cancel();
    _frames.close();
    super.dispose();
  }
}
