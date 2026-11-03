import 'gamepad.dart';

enum InputStatus {
  waiting,
  live,
  neutralRequired,
  paused,
  disconnected,
  stale,
  error,
}

class InputSession {
  Map<String, GamepadDevice> devices = {};
  Map<String, GamepadState> _raw = {};
  String? selectedId;
  bool _autoSelect = true;
  bool _enabled = true;
  bool _needsNeutral = false;
  bool _healthy = false;
  InputStatus status = InputStatus.waiting;
  GamepadState state = GamepadState.neutral;
  GamepadState raw = GamepadState.neutral;
  InputNormalizer normalizer = InputNormalizer();
  Duration? lastPacket;
  GamepadDevice? get device => devices[selectedId];

  void accept(Map<String, dynamic> event, Duration now) {
    if (event['version'] != 1) {
      throw const FormatException('Unsupported protocol');
    }
    if (event['type'] == 'heartbeat') {
      // Heartbeats do not recover a stale session without a full snapshot.
      if (status != InputStatus.stale && status != InputStatus.error) {
        lastPacket = now;
      }
      return;
    }
    if (event['type'] != 'snapshot') {
      throw const FormatException('Unknown packet');
    }
    final nextDevices = <String, GamepadDevice>{};
    final nextStates = <String, GamepadState>{};
    for (final item in event['devices'] as List) {
      final data = item as Map;
      final device = GamepadDevice.fromWire(data);
      if (nextDevices.containsKey(device.id)) {
        throw const FormatException('Duplicate device');
      }
      nextDevices[device.id] = device;
      nextStates[device.id] = GamepadState.fromWire(data['values'] as Map);
    }
    _healthy = true;
    devices = Map.unmodifiable(nextDevices);
    _raw = nextStates;
    lastPacket = now;
    if (selectedId != null && !devices.containsKey(selectedId)) {
      selectedId = null;
      status = InputStatus.disconnected;
      _needsNeutral = true;
    }
    if (_autoSelect && devices.isNotEmpty) {
      selectedId = devices.keys.first;
      _autoSelect = false;
      _needsNeutral = true;
    }
    _update();
  }

  void select(String id) {
    if (!devices.containsKey(id)) return;
    selectedId = id;
    _autoSelect = false;
    _needsNeutral = true;
    _update();
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
    _needsNeutral = true;
    if (enabled) {
      _healthy = false;
      status = InputStatus.neutralRequired;
    }
    _update();
  }

  void setDeadZone(double value) {
    normalizer = InputNormalizer(deadZone: value);
    _update();
  }

  void checkTimeout(
    Duration now, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) {
    if (lastPacket != null && now - lastPacket! > timeout) {
      invalidate(InputStatus.stale);
    }
  }

  void invalidate([InputStatus reason = InputStatus.error]) {
    status = reason;
    _healthy = false;
    _needsNeutral = true;
    state = GamepadState.neutral;
    raw = GamepadState.neutral;
  }

  void _update() {
    raw = _healthy
        ? (_raw[selectedId] ?? GamepadState.neutral)
        : GamepadState.neutral;
    state = GamepadState.neutral;
    if (!_enabled) {
      status = InputStatus.paused;
      return;
    }
    if (!_healthy) return;
    if (device == null) {
      if (status != InputStatus.disconnected) status = InputStatus.waiting;
      return;
    }
    final next = normalizer.normalize(raw);
    if (_needsNeutral && !next.isNeutral) {
      status = InputStatus.neutralRequired;
      return;
    }
    _needsNeutral = false;
    state = next;
    status = InputStatus.live;
  }
}
