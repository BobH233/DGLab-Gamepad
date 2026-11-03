import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/control/control_state.dart';
import 'package:dglab_gamepad/control/models.dart';

void main() {
  test('touch mapping uses a center peak and three frequency bands', () {
    final center = mapTouchPoint(x: 0.5, y: 0.5, intensityCeiling: 120);
    expect(center.intensity, 120);
    expect(center.frequencyMs, closeTo(10, 0.0001));
    expect(center.frequencyHz, 100);

    expect(mapTouchPoint(x: 0, y: 0, intensityCeiling: 120).intensity, 0);
    expect(mapTouchPoint(x: 1, y: 1, intensityCeiling: 120).intensity, 0);
    expect(
      mapTouchPoint(x: 0.5, y: 0, intensityCeiling: 120).frequencyMs,
      closeTo(100, 0.0001),
    );
    expect(
      mapTouchPoint(x: 0.5, y: 1, intensityCeiling: 120).frequencyMs,
      closeTo(100, 0.0001),
    );
    expect(
      mapTouchPoint(x: 0.5, y: 1 / 3, intensityCeiling: 120).frequencyMs,
      closeTo(10, 0.0001),
    );
  });

  test(
    'touch output is silent until pressed and uses live channel strength',
    () {
      final state = ControlState()
        ..touchMode = true
        ..touchChannel = 'A';
      state.channels['A']!.base = 120;
      state.channels['B']!
        ..base = 44
        ..enabled = true;

      var frame = state.frame();
      expect(frame.channels['A']!['enabled'], false);
      expect(frame.channels['A']!['intensity'], 0);
      expect(frame.channels['B']!['enabled'], true);
      expect(frame.channels['B']!['intensity'], 44);

      state.touchPoint = const TouchPoint(0.5, 0.5);
      frame = state.frame();
      expect(frame.channels['A']!['enabled'], true);
      expect(frame.channels['A']!['intensity'], 120);
      expect(frame.channels['A']!['frequencyMs'], 10);
      expect(frame.channels['A']!['waveformIntensity'], 100);
      expect(frame.channels['A']!['balance'], 128);
      expect(frame.channels['B']!['intensity'], 44);

      state.touchPoint = const TouchPoint(0.5, 0.5, active: false);
      frame = state.frame();
      expect(frame.channels['A']!['enabled'], false);
      expect(frame.channels['A']!['intensity'], 0);
    },
  );

  test('touch frequency and balance convert to Coyote protocol values', () {
    expect(encodeWaveformFrequency(10), 10);
    expect(encodeWaveformFrequency(100), 100);
    expect(encodeWaveformFrequency(120), 104);
    expect(encodeWaveformFrequency(600), 200);
    expect(encodeWaveformFrequency(1000), 240);
    expect(encodeBalance(0), 0);
    expect(encodeBalance(0.5), 128);
    expect(encodeBalance(1), 255);
  });
}
