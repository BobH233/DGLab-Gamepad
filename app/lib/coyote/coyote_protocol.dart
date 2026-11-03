import 'dart:typed_data';

import '../control/models.dart';
import '../control/output_waveform_trace.dart';

const coyoteMainServiceUuid = '0000180c-0000-1000-8000-00805f9b34fb';
const coyoteBatteryServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
const coyoteWriteCharacteristicUuid = '0000150a-0000-1000-8000-00805f9b34fb';
const coyoteNotifyCharacteristicUuid = '0000150b-0000-1000-8000-00805f9b34fb';
const coyoteBatteryCharacteristicUuid = '00001500-0000-1000-8000-00805f9b34fb';
const coyoteDeviceNamePrefix = '47';
const coyotePulseInterval = Duration(milliseconds: 100);

class CoyotePacketEncoder {
  int _nextStrengthSequence = 1;
  int _sentStrengthA = 0;
  int _sentStrengthB = 0;
  final OutputPulseSequencer _pulses = OutputPulseSequencer();

  Uint8List encode(
    OutputFrame? frame, {
    bool forceStrength = false,
    bool silence = false,
    bool allowStrengthChange = true,
  }) {
    final strengthA = silence ? 0 : _strength(frame, 'A');
    final strengthB = silence ? 0 : _strength(frame, 'B');
    var changed = 0;
    if (allowStrengthChange) {
      if (forceStrength || strengthA != _sentStrengthA) changed |= 0xC;
      if (forceStrength || strengthB != _sentStrengthB) changed |= 0x3;
    }

    final pulseA = silence
        ? _decodePulse(_blankPulse)
        : _pulses.next(frame, 'A').bytes;
    final pulseB = silence
        ? _decodePulse(_blankPulse)
        : _pulses.next(frame, 'B').bytes;

    final packet = Uint8List(20);
    packet[0] = 0xB0;
    if (changed == 0) {
      packet[1] = 0;
    } else {
      packet[1] = _nextStrengthSequence << 4 | changed;
      _nextStrengthSequence = _nextStrengthSequence % 15 + 1;
    }
    packet[2] = strengthA;
    packet[3] = strengthB;
    packet.setRange(4, 12, pulseA);
    packet.setRange(12, 20, pulseB);
    if (changed != 0) {
      _sentStrengthA = strengthA;
      _sentStrengthB = strengthB;
    }
    return packet;
  }

  int _strength(OutputFrame? frame, String channel) {
    final value = frame?.channels[channel]?['intensity'];
    return ((value as num?)?.round() ?? 0).clamp(0, 200);
  }

  List<int> _decodePulse(String value) => [
    for (var i = 0; i < 8; i++)
      int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
  ];

  static const _blankPulse = '0A0A0A0A00000000';

  Uint8List encodeBalance({
    required int frequencyBalanceA,
    required int frequencyBalanceB,
    required int pulseBalanceA,
    required int pulseBalanceB,
  }) => Uint8List.fromList([
    0xBF,
    201,
    201,
    frequencyBalanceA.clamp(0, 255),
    frequencyBalanceB.clamp(0, 255),
    pulseBalanceA.clamp(0, 255),
    pulseBalanceB.clamp(0, 255),
  ]);
}
