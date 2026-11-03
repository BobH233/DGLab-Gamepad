import 'dart:math' as math;

enum Control {
  south,
  east,
  west,
  north,
  leftShoulder,
  rightShoulder,
  leftTrigger,
  rightTrigger,
  leftStick,
  rightStick,
  leftX,
  leftY,
  rightX,
  rightY,
  up,
  down,
  left,
  right,
  menu,
  view,
  home,
  share,
}

final _controlsByName = {for (final c in Control.values) c.name: c};

double finiteUnit(Object? value, {bool signed = false}) {
  if (value is! num || !value.isFinite) return 0;
  return value.toDouble().clamp(signed ? -1.0 : 0.0, 1.0);
}

bool isAxis(Control c) => const {
  Control.leftX,
  Control.leftY,
  Control.rightX,
  Control.rightY,
}.contains(c);

class GamepadDevice {
  final String id;
  final String name;
  final String family;
  final String transport;
  final Set<Control> capabilities;
  final Map<String, dynamic> metadata;

  GamepadDevice.fromWire(Map<dynamic, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String? ?? 'Gamepad',
      family = data['family'] as String? ?? 'generic',
      transport = data['transport'] as String? ?? 'system',
      capabilities = Set.unmodifiable(
        (data['capabilities'] as List? ?? [])
            .whereType<String>()
            .map((name) => _controlsByName[name])
            .whereType<Control>(),
      ),
      metadata = Map.unmodifiable(Map<String, dynamic>.from(data));

  String label(Control c) {
    final face = switch (family) {
      'playstation' => ['×', '○', '□', '△'],
      'nintendo' => ['B', 'A', 'Y', 'X'],
      'xbox' => ['A', 'B', 'X', 'Y'],
      _ => ['S', 'E', 'W', 'N'],
    };
    if (c.index <= Control.north.index) return face[c.index];
    return switch (c) {
      Control.leftShoulder => family == 'playstation' ? 'L1' : 'LB',
      Control.rightShoulder => family == 'playstation' ? 'R1' : 'RB',
      Control.leftTrigger => family == 'playstation' ? 'L2' : 'LT',
      Control.rightTrigger => family == 'playstation' ? 'R2' : 'RT',
      Control.leftStick => 'L3',
      Control.rightStick => 'R3',
      Control.leftX => 'LX',
      Control.leftY => 'LY',
      Control.rightX => 'RX',
      Control.rightY => 'RY',
      Control.up => '↑',
      Control.down => '↓',
      Control.left => '←',
      Control.right => '→',
      Control.menu => 'MENU',
      Control.view => 'VIEW',
      Control.home => 'HOME',
      Control.share => 'SHARE',
      _ => c.name,
    };
  }
}

class GamepadState {
  final Map<Control, double> values;
  const GamepadState._(this.values);
  static const neutral = GamepadState._({});
  factory GamepadState(Map<Control, double> values) =>
      GamepadState._(Map.unmodifiable(values));
  factory GamepadState.fromWire(Map<dynamic, dynamic> data) => GamepadState({
    for (final e in data.entries)
      if (_controlsByName[e.key] case final Control c)
        c: finiteUnit(e.value, signed: isAxis(c)),
  });
  double operator [](Control c) => values[c] ?? 0;
  bool pressed(Control c) => this[c] > 0.5;
  bool get isNeutral => values.values.every((v) => v.abs() < 0.02);
  Map<String, double> toJson() => {
    for (final e in values.entries) e.key.name: e.value,
  };
}

class InputNormalizer {
  final double deadZone;
  InputNormalizer({this.deadZone = 0.12}) {
    if (!deadZone.isFinite || deadZone < 0 || deadZone >= 1) {
      throw ArgumentError.value(deadZone, 'deadZone');
    }
  }
  GamepadState normalize(GamepadState raw) {
    final result = <Control, double>{
      for (final e in raw.values.entries)
        e.key: finiteUnit(e.value, signed: isAxis(e.key)),
    };
    for (final pair in [
      (Control.leftX, Control.leftY),
      (Control.rightX, Control.rightY),
    ]) {
      final x = result[pair.$1] ?? 0;
      final y = result[pair.$2] ?? 0;
      final radius = math.sqrt(x * x + y * y);
      final scale = radius <= deadZone
          ? 0.0
          : ((math.min(radius, 1) - deadZone) / (1 - deadZone)) / radius;
      result[pair.$1] = scale == 0 ? 0.0 : x * scale;
      result[pair.$2] = scale == 0 ? 0.0 : y * scale;
    }
    return GamepadState(result);
  }
}
