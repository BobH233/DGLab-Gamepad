import 'dart:typed_data';

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
    final sample = OutputPulseSequencer().sample;
    final packet = encoder.encode(
      sample(frame(a: 80, b: 120)),
      forceStrength: true,
    );

    expect(packet, hasLength(20));
    expect(packet[0], 0xB0);
    expect(packet[1], 0x0F);
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
    final sample = OutputPulseSequencer().sample;
    encoder.encode(sample(frame(a: 80, b: 120)), forceStrength: true);
    final unchanged = encoder.encode(sample(frame(a: 80, b: 120)));
    expect(unchanged[1], 0x00);

    final changedA = encoder.encode(sample(frame(a: 90, b: 120)));
    expect(changedA[1], 0x0C);
    expect(changedA[2], 90);
    expect(changedA[3], 120);
  });

  test('inactive time advances the cached waveform phase', () {
    final encoder = CoyotePacketEncoder();
    final sample = OutputPulseSequencer().sample;
    final active = OutputFrame(1, {
      'A': {'enabled': true, 'intensity': 80, 'waveformId': waveforms[0].id},
      'B': {'enabled': false, 'intensity': 0, 'waveformId': waveforms[1].id},
    });
    final inactive = OutputFrame(2, {
      'A': {'enabled': false, 'intensity': 0, 'waveformId': waveforms[0].id},
      'B': {'enabled': false, 'intensity': 0, 'waveformId': waveforms[1].id},
    });

    final first = encoder.encode(sample(active), forceStrength: true);
    final stopped = encoder.encode(sample(inactive));
    final restarted = encoder.encode(sample(active));

    expect(stopped.sublist(4, 12), [10, 10, 10, 10, 0, 0, 0, 0]);
    expect(restarted.sublist(4, 12), isNot(first.sublist(4, 12)));
    expect(restarted.sublist(4, 12), [
      for (var i = 0; i < 8; i++)
        int.parse(
          waveforms[0].pulseData[2].substring(i * 2, i * 2 + 2),
          radix: 16,
        ),
    ]);
  });

  test('absolute strength changes never request an acknowledgement', () {
    final encoder = CoyotePacketEncoder();
    final sample = OutputPulseSequencer().sample;
    for (var strength = 0; strength <= 200; strength++) {
      final packet = encoder.encode(
        sample(frame(a: strength, b: 200 - strength)),
      );
      expect(packet[1] >> 4, 0);
      expect(packet[2], strength);
      expect(packet[3], 200 - strength);
      if (strength > 0) expect(packet[1] & 0xF, 0xF);
    }
  });

  test('silence packet clears both strengths and pulses', () {
    final packet = CoyotePacketEncoder().encode(
      null,
      forceStrength: true,
      silence: true,
    );
    expect(packet, hasLength(20));
    expect(packet[1], 0x0F);
    expect(packet[2], 0);
    expect(packet[3], 0);
    expect(packet.sublist(4, 8), everyElement(0x0A));
    expect(packet.sublist(8, 12), everyElement(0));
    expect(packet.sublist(12, 16), everyElement(0x0A));
    expect(packet.sublist(16, 20), everyElement(0));
  });

  test('dynamic touch frame overrides preset frequency and pulse width', () {
    Uint8List encode(double frequencyMs) {
      return CoyotePacketEncoder().encode(
        OutputPulseSequencer().sample(
          OutputFrame(1, {
            'A': {
              'intensity': 90,
              'enabled': true,
              'waveformId': waveforms.first.id,
              'frequencyMs': frequencyMs,
              'waveformIntensity': 100,
            },
            'B': {
              'intensity': 0,
              'enabled': false,
              'waveformId': waveforms[1].id,
            },
          }),
        ),
        forceStrength: true,
      );
    }

    final highFrequency = encode(10);
    final lowFrequency = encode(100);
    expect(highFrequency.sublist(4, 8), everyElement(10));
    expect(highFrequency.sublist(8, 12), everyElement(100));
    expect(lowFrequency.sublist(4, 8), everyElement(100));
    expect(lowFrequency.sublist(8, 12), everyElement(100));
  });

  test('output pulse sequencer restarts deterministically', () {
    final sequencer = OutputPulseSequencer();
    final first = OutputFrame(1, {
      'A': {'enabled': true, 'waveformId': waveforms[0].id},
      'B': {'enabled': true, 'waveformId': waveforms[1].id},
    });
    final other = OutputFrame(2, {
      'A': {'enabled': true, 'waveformId': waveforms[2].id},
      'B': {'enabled': true, 'waveformId': waveforms[1].id},
    });

    final initial = sequencer.next(first, 'A').samples;
    final initialValues = initial
        .map((sample) => [sample.frequency, sample.strength])
        .toList();
    expect(initialValues, [
      for (final sample in waveforms[0].samples.take(4))
        [sample.frequency, sample.strength],
    ]);
    sequencer.reset();
    expect(
      sequencer
          .next(first, 'A')
          .samples
          .map((sample) => [sample.frequency, sample.strength]),
      initialValues,
    );
    sequencer.next(other, 'A');
    expect(
      sequencer
          .next(first, 'A')
          .samples
          .map((sample) => [sample.frequency, sample.strength]),
      initialValues,
    );
  });

  test('the same waveform cycle repeats without drift', () {
    final sequencer = OutputPulseSequencer();
    final source = OutputFrame(1, {
      'A': {'enabled': true, 'intensity': 136, 'waveformId': waveforms[2].id},
      'B': {'enabled': false},
    });
    final cycleLength = waveforms[2].pulseData.length;
    final cycle = [
      for (var i = 0; i < cycleLength; i++) sequencer.next(source, 'A').bytes,
    ];
    final repeated = [
      for (var i = 0; i < cycleLength; i++) sequencer.next(source, 'A').bytes,
    ];
    expect(repeated, cycle);
  });

  test(
    'live waveform trace follows core output without a BLE connection',
    () async {
      final trace = OutputWaveformTrace();
      trace.accept(
        OutputFrame(1, {
          'A': {
            'enabled': true,
            'intensity': 80,
            'waveformId': waveforms[0].id,
          },
          'B': {
            'enabled': false,
            'intensity': 0,
            'waveformId': waveforms[1].id,
          },
        }),
      );

      await Future<void>.delayed(
        OutputWaveformTrace.sampleInterval + const Duration(milliseconds: 20),
      );
      final samples = trace.samplesFor('A');
      expect(samples, hasLength(4));
      expect(samples.map((item) => item.frequency), [
        for (final sample in waveforms[0].samples.take(4)) sample.frequency,
      ]);
      expect(samples.map((item) => item.strength), [
        for (final sample in waveforms[0].samples.take(4)) sample.strength,
      ]);
      expect(trace.samplesFor('B'), isEmpty);

      trace.accept(
        OutputFrame(2, {
          'A': {'enabled': false},
          'B': {'enabled': false},
        }),
      );
      expect(trace.samplesFor('A'), hasLength(4));
      await Future<void>.delayed(
        OutputWaveformTrace.sampleInterval + const Duration(milliseconds: 20),
      );
      final withGap = trace.samplesFor('A');
      expect(withGap.length, greaterThan(4));
      expect(withGap.skip(4), everyElement(const PulseSample(10, 0)));

      trace.accept(
        OutputFrame(3, {
          'A': {
            'enabled': true,
            'intensity': 80,
            'waveformId': waveforms[0].id,
          },
          'B': {'enabled': false},
        }),
      );
      await Future<void>.delayed(
        OutputWaveformTrace.sampleInterval + const Duration(milliseconds: 20),
      );
      expect(trace.samplesFor('A').length, greaterThan(withGap.length));
      trace.dispose();
    },
  );

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
