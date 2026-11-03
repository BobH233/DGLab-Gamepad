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

    final packet = Uint8List(20);
    packet[0] = 0xB0;
    packet[1] = changed == 0 ? 0 : 0xE0 | changed;
    packet[2] = strengthA;
    packet[3] = strengthB;
    packet.setRange(4, 12, _decodePulse(pulseA));
    packet.setRange(12, 20, _decodePulse(pulseB));
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
    final values = frame?.channels[channel];
    final frequencyMs = values?['frequencyMs'];
    final waveformIntensity = values?['waveformIntensity'];
    if (frequencyMs is num && waveformIntensity is num) {
      final frequency = encodeWaveformFrequency(frequencyMs.toDouble());
      final strength = waveformIntensity.round().clamp(0, 100);
      return [
        for (var i = 0; i < 4; i++) frequency.toRadixString(16).padLeft(2, '0'),
        for (var i = 0; i < 4; i++) strength.toRadixString(16).padLeft(2, '0'),
      ].join();
    }
    final waveformId = values?['waveformId'];
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
