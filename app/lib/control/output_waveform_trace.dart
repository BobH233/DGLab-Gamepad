import 'dart:async';

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
  String? _waveformA;
  String? _waveformB;

  OutputPulseFrame next(OutputFrame? frame, String channel) {
    final values = frame?.channels[channel];
    final frequencyMs = values?['frequencyMs'];
    final waveformIntensity = values?['waveformIntensity'];
    if (frequencyMs is num && waveformIntensity is num) {
      _resetChannel(channel);
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
      _resetChannel(channel);
      return OutputPulseFrame.blank();
    }

    final previousWaveform = channel == 'A' ? _waveformA : _waveformB;
    if (previousWaveform != waveform.id) {
      _resetChannel(channel);
      if (channel == 'A') {
        _waveformA = waveform.id;
      } else {
        _waveformB = waveform.id;
      }
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

  void reset() {
    resetChannel('A');
    resetChannel('B');
  }

  void resetChannel(String channel) {
    _resetChannel(channel);
  }

  void _resetChannel(String channel) {
    if (channel == 'A') {
      _indexA = 0;
      _waveformA = null;
    } else {
      _indexB = 0;
      _waveformB = null;
    }
  }

  static List<int> _decodePulse(String value) => [
    for (var i = 0; i < 8; i++)
      int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
  ];
}

class OutputWaveformTrace extends ChangeNotifier implements OutputSink {
  static const maxSamples = 400;
  static const sampleInterval = Duration(milliseconds: 100);

  final OutputPulseSequencer _sequencer = OutputPulseSequencer();
  final Map<String, List<PulseSample>> _samples = {
    for (final id in channelIds) id: const [],
  };
  late final Timer _timer;
  OutputFrame? _latestFrame;
  Set<String> _activeChannels = const {};
  final Map<String, String?> _sources = {};

  OutputWaveformTrace({bool autoStart = true}) {
    _timer = Timer.periodic(sampleInterval, (_) => _sample());
    if (!autoStart) _timer.cancel();
  }

  List<PulseSample> samplesFor(String channel) => _samples[channel] ?? const [];

  @override
  void accept(OutputFrame frame) {
    final active = {
      for (final id in channelIds)
        if (frame.channels[id]?['enabled'] == true) id,
    };
    _latestFrame = frame;
    if (active.isEmpty) {
      _sequencer.reset();
      _sources.clear();
      _clearSamples();
      _activeChannels = active;
      return;
    }
    if (_activeChannels.isEmpty) {
      _sequencer.reset();
    }
    var changed = false;
    for (final id in channelIds) {
      final values = frame.channels[id];
      if (!active.contains(id)) {
        if (_activeChannels.contains(id)) {
          _samples[id] = const [];
          changed = true;
        }
        _sequencer.resetChannel(id);
        _sources.remove(id);
        continue;
      }
      final source =
          values?['frequencyMs'] is num && values?['waveformIntensity'] is num
          ? 'touch'
          : 'waveform:${values?['waveformId']}';
      if (_sources[id] != source) {
        _samples[id] = const [];
        _sequencer.resetChannel(id);
        _sources[id] = source;
        changed = true;
      }
    }
    _activeChannels = active;
    if (changed) notifyListeners();
  }

  void _sample() {
    final frame = _latestFrame;
    if (frame == null || _activeChannels.isEmpty) return;
    var changed = false;
    for (final id in channelIds) {
      if (!_activeChannels.contains(id)) {
        if (_samples[id]!.isNotEmpty) {
          _samples[id] = const [];
          changed = true;
        }
        continue;
      }
      final pulse = _sequencer.next(frame, id);
      final next = [..._samples[id]!, ...pulse.samples];
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

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
