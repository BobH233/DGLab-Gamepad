import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad_core/gamepad_core.dart';

Map<String, dynamic> pad(String id, [Map<String, double> values = const {}]) =>
    {
      'id': id,
      'name': id,
      'family': 'xbox',
      'capabilities': ['south', 'leftX', 'leftY'],
      'values': values,
    };
Map<String, dynamic> packet(List<Map<String, dynamic>> devices) => {
  'version': 1,
  'type': 'snapshot',
  'devices': devices,
};
void main() {
  test('Radial dead zone is continuous, bounded and preserves direction', () {
    final n = InputNormalizer();
    expect(n.normalize(GamepadState({Control.leftX: 0.1}))[Control.leftX], 0);
    expect(n.normalize(GamepadState({Control.leftX: 0.12}))[Control.leftX], 0);
    final diagonal = n.normalize(
      GamepadState({Control.leftX: 1, Control.leftY: -1}),
    );
    expect(diagonal[Control.leftX], closeTo(math.sqrt(0.5), 0.00001));
    expect(diagonal[Control.leftY], closeTo(-math.sqrt(0.5), 0.00001));
    expect(n.normalize(GamepadState({Control.leftX: 1}))[Control.leftX], 1);
    expect(() => InputNormalizer(deadZone: 1), throwsArgumentError);
  });
  test('Non-finite and out-of-range data never escape normalization', () {
    final state = GamepadState.fromWire({
      'leftX': double.nan,
      'rightY': double.infinity,
      'leftTrigger': 10,
      'south': -3,
      'unknown': 1,
    });
    expect(state[Control.leftX], 0);
    expect(state[Control.rightY], 0);
    expect(state[Control.leftTrigger], 1);
    expect(state[Control.south], 0);
  });
  test('First connection while held requires neutral before activation', () {
    final s = InputSession();
    s.accept(
      packet([
        pad('a', {'south': 1}),
      ]),
      Duration.zero,
    );
    expect(s.status, InputStatus.neutralRequired);
    expect(s.state.isNeutral, true);
    s.accept(packet([pad('a')]), const Duration(milliseconds: 1));
    expect(s.status, InputStatus.live);
    s.accept(
      packet([
        pad('a', {'south': 1}),
      ]),
      const Duration(milliseconds: 2),
    );
    expect(s.state.pressed(Control.south), true);
  });
  test(
    'Disconnect clears state and never silently switches to another controller',
    () {
      final s = InputSession();
      s.accept(packet([pad('a'), pad('b')]), Duration.zero);
      s.accept(
        packet([
          pad('a', {'south': 1}),
          pad('b'),
        ]),
        const Duration(milliseconds: 1),
      );
      s.accept(
        packet([
          pad('b', {'south': 1}),
        ]),
        const Duration(milliseconds: 2),
      );
      expect(s.selectedId, isNull);
      expect(s.state.isNeutral, true);
      expect(s.status, InputStatus.disconnected);
      s.select('b');
      expect(s.status, InputStatus.neutralRequired);
      s.accept(packet([pad('b')]), const Duration(milliseconds: 3));
      expect(s.status, InputStatus.live);
    },
  );
  test('Inactive device input cannot affect selected device', () {
    final s = InputSession();
    s.accept(packet([pad('a'), pad('b')]), Duration.zero);
    s.accept(
      packet([
        pad('a'),
        pad('b', {'south': 1}),
      ]),
      const Duration(milliseconds: 1),
    );
    expect(s.state.isNeutral, true);
  });
  test('Timeout clears held input; settings cannot revive cached state', () {
    final s = InputSession();
    s.accept(packet([pad('a')]), Duration.zero);
    s.accept(
      packet([
        pad('a', {'south': 1}),
      ]),
      const Duration(milliseconds: 10),
    );
    s.checkTimeout(const Duration(seconds: 2));
    expect(s.status, InputStatus.stale);
    expect(s.state.isNeutral, true);
    s.setDeadZone(0.2);
    expect(s.state.isNeutral, true);
    expect(s.status, InputStatus.stale);
    s.accept(
      packet([
        pad('a', {'south': 1}),
      ]),
      const Duration(seconds: 3),
    );
    expect(s.status, InputStatus.neutralRequired);
    s.accept(packet([pad('a')]), const Duration(seconds: 4));
    expect(s.status, InputStatus.live);
  });
  test('Stationary held input stays valid while native snapshots arrive', () {
    final s = InputSession();
    s.accept(packet([pad('a')]), Duration.zero);
    for (var i = 1; i < 20; i++) {
      final now = Duration(seconds: i);
      s.accept(
        packet([
          pad('a', {'leftTrigger': 0.7}),
        ]),
        now,
      );
      s.checkTimeout(now);
      expect(s.state[Control.leftTrigger], 0.7);
    }
  });
  test('Pause and resume require fresh neutral input', () {
    final s = InputSession();
    s.accept(packet([pad('a')]), Duration.zero);
    s.setEnabled(false);
    s.accept(
      packet([
        pad('a', {'south': 1}),
      ]),
      const Duration(milliseconds: 1),
    );
    expect(s.status, InputStatus.paused);
    expect(s.state.isNeutral, true);
    s.setEnabled(true);
    expect(s.state.isNeutral, true);
    s.accept(
      packet([
        pad('a', {'south': 1}),
      ]),
      const Duration(milliseconds: 2),
    );
    expect(s.status, InputStatus.neutralRequired);
    s.accept(packet([pad('a')]), const Duration(milliseconds: 3));
    expect(s.status, InputStatus.live);
  });
  test('Invalid snapshot is rejected atomically', () {
    final s = InputSession();
    s.accept(packet([pad('a')]), Duration.zero);
    expect(
      () => s.accept(packet([pad('b'), pad('b')]), Duration.zero),
      throwsFormatException,
    );
    expect(s.selectedId, 'a');
    expect(s.devices.keys, ['a']);
  });
  test('Button labels never change physical control identity', () {
    final xbox = GamepadDevice.fromWire(pad('a'));
    final ps = GamepadDevice.fromWire({...pad('b'), 'family': 'playstation'});
    expect(xbox.label(Control.south), 'A');
    expect(ps.label(Control.south), '×');
  });
}
