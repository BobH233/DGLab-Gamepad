import 'dart:typed_data';

import '../control/output_waveform_trace.dart';

const coyoteMainServiceUuid = '0000180c-0000-1000-8000-00805f9b34fb';
const coyoteBatteryServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
const coyoteWriteCharacteristicUuid = '0000150a-0000-1000-8000-00805f9b34fb';
const coyoteNotifyCharacteristicUuid = '0000150b-0000-1000-8000-00805f9b34fb';
const coyoteBatteryCharacteristicUuid = '00001500-0000-1000-8000-00805f9b34fb';
const coyoteDeviceNamePrefix = '47';
const coyotePulseInterval = OutputPulseClock.interval;

class CoyotePacketEncoder {
  int _sentStrengthA = 0;
  int _sentStrengthB = 0;

  Uint8List encode(
    OutputPulseSnapshot? pulse, {
    bool forceStrength = false,
    bool silence = false,
  }) {
    final strengthA = silence ? 0 : _strength(pulse, 'A');
    final strengthB = silence ? 0 : _strength(pulse, 'B');
    var changed = 0;
    if (forceStrength || strengthA != _sentStrengthA) changed |= 0xC;
    if (forceStrength || strengthB != _sentStrengthB) changed |= 0x3;

    final blank = OutputPulseFrame.blank().bytes;
    final pulseA = silence ? blank : pulse?.a.bytes ?? blank;
    final pulseB = silence ? blank : pulse?.b.bytes ?? blank;

    final packet = Uint8List(20);
    packet[0] = 0xB0;
    packet[1] = changed;
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

  int _strength(OutputPulseSnapshot? pulse, String channel) {
    final values = pulse?.frame.channels[channel];
    if (values?['enabled'] != true) return 0;
    final value = values?['intensity'];
    return ((value as num?)?.round() ?? 0).clamp(0, 200);
  }

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
