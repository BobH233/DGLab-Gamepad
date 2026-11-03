import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/coyote/coyote_protocol.dart';

OutputFrame frame({required int a, required int b}) => OutputFrame(1, {
  'A': {'intensity': a, 'enabled': a > 0, 'waveformId': waveforms[0].id},
  'B': {'intensity': b, 'enabled': b > 0, 'waveformId': waveforms[1].id},
});

void main() {
  test('Coyote 3 packet carries strengths and both waveform frames', () {
    final encoder = CoyotePacketEncoder();
    final packet = encoder.encode(frame(a: 80, b: 120), forceStrength: true);

    expect(packet, hasLength(21));
    expect(packet[0], 0xB0);
    expect(packet[1], 0x0E);
    expect(packet[2], 0x0F);
    expect(packet[3], 80);
    expect(packet[4], 120);
    expect(packet.sublist(5, 13), [
      for (var i = 0; i < 8; i++)
        int.parse(
          waveforms[0].pulseData.first.substring(i * 2, i * 2 + 2),
          radix: 16,
        ),
    ]);
    expect(packet.sublist(13, 21), [
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
    expect(unchanged[2], 0x00);

    final changedA = encoder.encode(frame(a: 90, b: 120));
    expect(changedA[1], 0x0E);
    expect(changedA[2], 0x0C);
    expect(changedA[3], 90);
    expect(changedA[4], 120);
  });

  test('silence packet clears both strengths and pulses', () {
    final packet = CoyotePacketEncoder().encode(
      null,
      forceStrength: true,
      silence: true,
    );
    expect(packet[1], 0x0E);
    expect(packet[2], 0x0F);
    expect(packet[3], 0);
    expect(packet[4], 0);
    expect(packet.sublist(5, 9), everyElement(0x0A));
    expect(packet.sublist(9, 13), everyElement(0));
    expect(packet.sublist(13, 17), everyElement(0x0A));
    expect(packet.sublist(17, 21), everyElement(0));
  });
}
