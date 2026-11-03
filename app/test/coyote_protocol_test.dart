import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/control/output_waveform_trace.dart';
import 'package:dglab_gamepad/coyote/coyote_protocol.dart';

OutputFrame frame({required int a, required int b}) => OutputFrame(1, {
  'A': {'intensity': a, 'enabled': a > 0, 'waveformId': waveforms[0].id},
  'B': {'intensity': b, 'enabled': b > 0, 'waveformId': waveforms[1].id},
});

void main() {
  test('Coyote 3 packet carries strengths and both waveform frames', () {
    final encoder = CoyotePacketEncoder();
    final packet = encoder.encode(frame(a: 80, b: 120), forceStrength: true);

    expect(packet, hasLength(20));
    expect(packet[0], 0xB0);
    expect(packet[1], 0x1F);
    expect(packet[2], 80);
    expect(packet[3], 120);
    expect(packet.sublist(4, 12), [
      for (var i = 0; i < 8; i++)
        int.parse(
          waveforms[0].pulseData.first.substring(i * 2, i * 2 + 2),
          radix: 16,
        ),
    ]);
    expect(packet.sublist(12, 20), [
      for (var i = 0; i < 8; i++)
        int.parse(
          waveforms[1].pulseData.first.substring(i * 2, i * 2 + 2),
          radix: 16,
        ),
    ]);
  });

  test('Coyote 3 packet marks only changed channels', () {
    final encoder = CoyotePacketEncoder();
    encoder.encode(frame(a: 80, b: 120), forceStrength: true);
    final unchanged = encoder.encode(frame(a: 80, b: 120));
    expect(unchanged[1], 0x00);

    final changedA = encoder.encode(frame(a: 90, b: 120));
    expect(changedA[1], 0x2C);
    expect(changedA[2], 90);
    expect(changedA[3], 120);
  });

  test('deferred strength change keeps waveform stream alive', () {
    final encoder = CoyotePacketEncoder();
    final first = encoder.encode(frame(a: 80, b: 120), forceStrength: true);
    final deferred = encoder.encode(
      frame(a: 90, b: 120),
      allowStrengthChange: false,
    );

    expect(first[1], 0x1F);
    expect(deferred[1], 0x00);
    expect(deferred.sublist(4, 12), isNot(first.sublist(4, 12)));

    final delivered = encoder.encode(frame(a: 90, b: 120));
    expect(delivered[1], 0x2C);
    expect(delivered[2], 90);
  });

  test('strength sequence cycles from 1 through F', () {
    final encoder = CoyotePacketEncoder();
    final sequences = <int>[];
    for (var strength = 1; strength <= 16; strength++) {
      sequences.add(encoder.encode(frame(a: strength, b: 0))[1] >> 4);
    }
    expect(sequences, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 1]);
  });

  test('silence packet clears both strengths and pulses', () {
    final packet = CoyotePacketEncoder().encode(
      null,
      forceStrength: true,
      silence: true,
    );
    expect(packet, hasLength(20));
    expect(packet[1], 0x1F);
    expect(packet[2], 0);
    expect(packet[3], 0);
    expect(packet.sublist(4, 8), everyElement(0x0A));
    expect(packet.sublist(8, 12), everyElement(0));
    expect(packet.sublist(12, 16), everyElement(0x0A));
    expect(packet.sublist(16, 20), everyElement(0));
  });

  test('dynamic touch frame overrides preset frequency and pulse width', () {
    final packet = CoyotePacketEncoder().encode(
      OutputFrame(1, {
        'A': {
          'intensity': 90,
          'enabled': true,
          'waveformId': waveforms.first.id,
          'frequencyMs': 10,
          'waveformIntensity': 100,
        },
        'B': {'intensity': 0, 'enabled': false, 'waveformId': waveforms[1].id},
      }),
      forceStrength: true,
    );

    expect(packet.sublist(4, 8), everyElement(10));
    expect(packet.sublist(8, 12), everyElement(100));
  });

  test('live waveform trace follows core output without a BLE connection', () {
    final trace = OutputWaveformTrace();
    trace.accept(
      OutputFrame(1, {
        'A': {'enabled': true, 'intensity': 80, 'waveformId': waveforms[0].id},
        'B': {'enabled': false, 'intensity': 0, 'waveformId': waveforms[1].id},
      }),
    );

    final samples = trace.samplesFor('A');
    expect(samples, hasLength(4));
    expect(samples.map((item) => item.sample.frequency), [
      for (final sample in waveforms[0].samples.take(4)) sample.frequency,
    ]);
    expect(samples.map((item) => item.sample.strength), [
      for (final sample in waveforms[0].samples.take(4)) sample.strength,
    ]);
    expect(trace.samplesFor('B'), isEmpty);
    expect(samples.last.seconds, greaterThan(samples.first.seconds));

    trace.accept(
      OutputFrame(2, {
        'A': {'enabled': false},
        'B': {'enabled': false},
      }),
    );
    expect(trace.samplesFor('A'), isEmpty);
    trace.dispose();
  });

  test(
    'balance packet preserves soft limits and writes both balance pairs',
    () {
      final packet = CoyotePacketEncoder().encodeBalance(
        frequencyBalanceA: 128,
        frequencyBalanceB: 128,
        pulseBalanceA: 0,
        pulseBalanceB: 0,
      );
      expect(packet, [0xBF, 201, 201, 128, 128, 0, 0]);
    },
  );
}
