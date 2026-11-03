import 'dart:typed_data';

import '../control/models.dart';

const coyoteMainServiceUuid = '0000180c-0000-1000-8000-00805f9b34fb';
const coyoteBatteryServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
const coyoteWriteCharacteristicUuid = '0000150a-0000-1000-8000-00805f9b34fb';
const coyoteNotifyCharacteristicUuid = '0000150b-0000-1000-8000-00805f9b34fb';
const coyoteBatteryCharacteristicUuid = '00001500-0000-1000-8000-00805f9b34fb';
const coyoteDeviceNamePrefix = '47';
const coyotePulseInterval = Duration(milliseconds: 100);

class CoyotePacketEncoder {
  int _sequence = 0;
  int _sentStrengthA = 0;
  int _sentStrengthB = 0;
  int _pulseIndexA = 0;
  int _pulseIndexB = 0;

  Uint8List encode(
    OutputFrame? frame, {
    bool forceStrength = false,
    bool silence = false,
  }) {
    final strengthA = silence ? 0 : _strength(frame, 'A');
    final strengthB = silence ? 0 : _strength(frame, 'B');
    var changed = 0;
    if (forceStrength || strengthA != _sentStrengthA) changed |= 0xC;
    if (forceStrength || strengthB != _sentStrengthB) changed |= 0x3;

    final pulseA = silence
        ? _blankPulse
        : _nextPulse(frame, 'A', () => _pulseIndexA, (v) => _pulseIndexA = v);
    final pulseB = silence
        ? _blankPulse
        : _nextPulse(frame, 'B', () => _pulseIndexB, (v) => _pulseIndexB = v);

    final packet = Uint8List(21);
    packet[0] = 0xB0;
    packet[1] = changed == 0 ? _sequence++ & 0x0F : 0x0E;
    packet[2] = changed;
    packet[3] = strengthA;
    packet[4] = strengthB;
    packet.setRange(5, 13, _decodePulse(pulseA));
    packet.setRange(13, 21, _decodePulse(pulseB));
    _sentStrengthA = strengthA;
    _sentStrengthB = strengthB;
    return packet;
  }

  int _strength(OutputFrame? frame, String channel) {
    final value = frame?.channels[channel]?['intensity'];
    return ((value as num?)?.round() ?? 0).clamp(0, 200);
  }

  String _nextPulse(
    OutputFrame? frame,
    String channel,
    int Function() index,
    void Function(int) updateIndex,
  ) {
    final waveformId = frame?.channels[channel]?['waveformId'];
    final waveform = waveforms
        .where((item) => item.id == waveformId)
        .firstOrNull;
    if (waveform == null || waveform.pulseData.isEmpty) return _blankPulse;
    final current = index() % waveform.pulseData.length;
    updateIndex((current + 1) % waveform.pulseData.length);
    return waveform.pulseData[current];
  }

  List<int> _decodePulse(String value) => [
    for (var i = 0; i < 8; i++)
      int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
  ];

  static const _blankPulse = '0A0A0A0A00000000';
}
