import 'package:dglab_gamepad/control/pulse_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses pulse points into paced V3 frames', () {
    final waveform = parsePulseWaveform(
      'Dungeonlab+pulse:2,1,16=0,0,0,1,1/0-1,100-1',
      name: '测试波形',
    );

    expect(waveform.isCustom, isTrue);
    expect(waveform.pulseData, [
      '0A0A0A0A00000000',
      '0A0A0A0A64646464',
      '0A0A0A0A00000000',
    ]);
  });

  test('keeps every exported control point strength', () {
    final waveform = parsePulseWaveform(
      'Dungeonlab+pulse:0,1,16=0,0,0,1,1/0-1,100-0,100-1',
      name: '曲线',
    );

    expect(waveform.pulseData, [
      '0A0A0A0A00000000',
      '0A0A0A0A64646464',
      '0A0A0A0A64646464',
    ]);
  });

  test('applies playback speed and pads the final V3 frame', () {
    final waveform = parsePulseWaveform(
      'Dungeonlab+pulse:0,4,16=0,0,0,1,1/0-1,100-1',
      name: '高速',
    );

    expect(waveform.pulseData, ['0A0A0A0A00640000']);
  });

  test('maps frequency indices through the Coyote slider table', () {
    final waveform = parsePulseWaveform(
      'Dungeonlab+pulse:0,1,16=0,83,0,3,1/100-1,100-1',
      name: '频率',
    );

    expect(waveform.pulseData, ['0A0A0A0A64646464', 'F0F0F0F064646464']);
  });

  test('appends the waveform rest period after all enabled sections', () {
    final waveform = parsePulseWaveform(
      'Dungeonlab+pulse:1,1,16=0,0,0,1,1/0-1,100-1'
      '+section+0,0,0,1,1/0-1,100-1',
      name: '休息',
    );

    expect(waveform.pulseData, [
      '0A0A0A0A00000000',
      '0A0A0A0A64646464',
      '0A0A0A0A00000000',
      '0A0A0A0A64646464',
      '0A0A0A0A00000000',
    ]);
  });

  test('accepts line breaks in shared pulse text', () {
    final waveform = parsePulseWaveform(
      'Dungeonlab+pulse:0,1,16=0,0,0,1,1/\r\n0-1,100-1',
      name: '多行',
    );

    expect(waveform.samples, hasLength(8));
  });

  test('rejects unsupported pulse input', () {
    expect(
      () => parsePulseWaveform('not-a-pulse', name: '错误'),
      throwsFormatException,
    );
    expect(
      () => parsePulseWaveform(
        'Dungeonlab+pulse:0,1,16=84,0,0,1,1/0-1,100-1',
        name: '错误',
      ),
      throwsFormatException,
    );
  });
}
