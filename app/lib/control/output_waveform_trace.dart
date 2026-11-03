import 'package:flutter/foundation.dart';

import 'models.dart';

class OutputPulseFrame {
  final List<int> bytes;
  final List<PulseSample> samples;

  OutputPulseFrame(List<int> bytes)
    : bytes = List.unmodifiable(bytes),
      samples = List.unmodifiable(decodePulseBytes(bytes));

  static OutputPulseFrame blank() =>
      OutputPulseFrame(const [10, 10, 10, 10, 0, 0, 0, 0]);
}

class OutputPulseSequencer {
  int _indexA = 0;
  int _indexB = 0;

  OutputPulseFrame next(OutputFrame? frame, String channel) {
    final values = frame?.channels[channel];
    final frequencyMs = values?['frequencyMs'];
    final waveformIntensity = values?['waveformIntensity'];
    if (frequencyMs is num && waveformIntensity is num) {
      final frequency = encodeWaveformFrequency(frequencyMs.toDouble());
      final strength = waveformIntensity.round().clamp(0, 100);
      return OutputPulseFrame([
        for (var i = 0; i < 4; i++) frequency,
        for (var i = 0; i < 4; i++) strength,
      ]);
    }

    final waveform = waveforms
        .where((item) => item.id == values?['waveformId'])
        .firstOrNull;
    if (waveform == null || waveform.pulseData.isEmpty) {
      return OutputPulseFrame.blank();
    }
    final index = channel == 'A' ? _indexA : _indexB;
    final current = index % waveform.pulseData.length;
    if (channel == 'A') {
      _indexA = (current + 1) % waveform.pulseData.length;
    } else {
      _indexB = (current + 1) % waveform.pulseData.length;
    }
    return OutputPulseFrame(_decodePulse(waveform.pulseData[current]));
  }

  static List<int> _decodePulse(String value) => [
    for (var i = 0; i < 8; i++)
      int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
  ];
}

class TimedPulseSample {
  final PulseSample sample;
  final double seconds;

  const TimedPulseSample(this.sample, this.seconds);
}

class OutputWaveformTrace extends ChangeNotifier implements OutputSink {
  static const maxSamples = 400;
  static const sampleInterval = Duration(milliseconds: 100);

  final Stopwatch _clock = Stopwatch()..start();
  final OutputPulseSequencer _sequencer = OutputPulseSequencer();
  final Map<String, List<TimedPulseSample>> _samples = {
    for (final id in channelIds) id: const [],
  };
  double? _lastSampleSeconds;

  double get nowSeconds => _clock.elapsedMicroseconds / 1000000;

  List<TimedPulseSample> samplesFor(String channel) =>
      _samples[channel] ?? const [];

  @override
  void accept(OutputFrame frame) {
    final active = {
      for (final id in channelIds)
        if (frame.channels[id]?['enabled'] == true) id,
    };
    if (active.isEmpty) {
      _lastSampleSeconds = null;
      _clearSamples();
      return;
    }

    final now = nowSeconds;
    if (_lastSampleSeconds case final previous?
        when now - previous < sampleInterval.inMicroseconds / 1000000) {
      return;
    }
    _lastSampleSeconds = now;
    var changed = false;
    for (final id in channelIds) {
      if (!active.contains(id)) {
        if (_samples[id]!.isNotEmpty) {
          _samples[id] = const [];
          changed = true;
        }
        continue;
      }
      final pulse = _sequencer.next(frame, id);
      final sampleSeconds = sampleInterval.inMicroseconds / 4 / 1000000;
      final next = [
        ..._samples[id]!,
        for (var i = 0; i < pulse.samples.length; i++)
          TimedPulseSample(
            pulse.samples[i],
            now - (pulse.samples.length - 1 - i) * sampleSeconds,
          ),
      ];
      if (next.length > maxSamples) {
        next.removeRange(0, next.length - maxSamples);
      }
      _samples[id] = List.unmodifiable(next);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _clearSamples() {
    var changed = false;
    for (final id in channelIds) {
      if (_samples[id]!.isNotEmpty) {
        _samples[id] = const [];
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
