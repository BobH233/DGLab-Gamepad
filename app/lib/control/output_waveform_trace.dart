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

class OutputPulseSnapshot {
  final OutputFrame frame;
  final OutputPulseFrame a;
  final OutputPulseFrame b;

  const OutputPulseSnapshot(this.frame, this.a, this.b);

  OutputPulseFrame forChannel(String id) => id == 'A' ? a : b;
}

class OutputPulseSequencer {
  int _indexA = 0;
  int _indexB = 0;
  String? _waveformA;
  String? _waveformB;

  OutputPulseSnapshot sample(OutputFrame frame) {
    OutputPulseFrame pulse(String id) {
      final value = next(frame, id);
      return frame.channels[id]?['enabled'] == true
          ? value
          : OutputPulseFrame.blank();
    }

    return OutputPulseSnapshot(frame, pulse('A'), pulse('B'));
  }

  OutputPulseFrame next(OutputFrame? frame, String channel) {
    final values = frame?.channels[channel];
    final frequencyMs = values?['frequencyMs'];
    final waveformIntensity = values?['waveformIntensity'];
    if (frequencyMs is num && waveformIntensity is num) {
      _prepareWaveform(channel, values?['waveformId']);
      _advance(channel);
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

    _prepareWaveform(channel, waveform.id);
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

  void _prepareWaveform(String channel, Object? waveformId) {
    final previousWaveform = channel == 'A' ? _waveformA : _waveformB;
    if (previousWaveform == waveformId) return;
    _resetChannel(channel);
    if (channel == 'A') {
      _waveformA = waveformId is String ? waveformId : null;
    } else {
      _waveformB = waveformId is String ? waveformId : null;
    }
  }

  void _advance(String channel) {
    final waveformId = channel == 'A' ? _waveformA : _waveformB;
    final waveform = waveforms
        .where((item) => item.id == waveformId)
        .firstOrNull;
    if (waveform == null || waveform.pulseData.isEmpty) return;
    final index = channel == 'A' ? _indexA : _indexB;
    final next = (index + 1) % waveform.pulseData.length;
    if (channel == 'A') {
      _indexA = next;
    } else {
      _indexB = next;
    }
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

class OutputPulseClock implements OutputSink {
  static const interval = Duration(milliseconds: 100);

  final OutputPulseSequencer _sequencer = OutputPulseSequencer();
  final StreamController<OutputPulseSnapshot> _pulses =
      StreamController.broadcast(sync: true);
  Timer? _timer;
  OutputFrame _latestFrame = OutputFrame(0, const {});
  OutputPulseSnapshot? _latestPulse;

  OutputPulseClock({bool autoStart = true}) {
    if (autoStart) {
      _timer = Timer.periodic(interval, (_) {
        final pulse = _sequencer.sample(_latestFrame);
        _latestPulse = pulse;
        _pulses.add(pulse);
      });
    }
  }

  Stream<OutputPulseSnapshot> get pulses => _pulses.stream;
  OutputPulseSnapshot? get latestPulse => _latestPulse;

  @override
  void accept(OutputFrame frame) => _latestFrame = frame;

  void dispose() {
    _timer?.cancel();
    unawaited(_pulses.close());
  }
}

class OutputWaveformTrace extends ChangeNotifier implements OutputSink {
  static const maxSamples = 400;
  static const sampleInterval = OutputPulseClock.interval;

  final OutputPulseClock clock;
  final bool _ownsClock;
  final Map<String, List<PulseSample>> _samples = {
    for (final id in channelIds) id: const [],
  };
  late final StreamSubscription<OutputPulseSnapshot> _subscription;

  OutputWaveformTrace({OutputPulseClock? clock, bool autoStart = true})
    : clock = clock ?? OutputPulseClock(autoStart: autoStart),
      _ownsClock = clock == null {
    _subscription = this.clock.pulses.listen(_sample);
  }

  List<PulseSample> samplesFor(String channel) => _samples[channel] ?? const [];

  @override
  void accept(OutputFrame frame) => clock.accept(frame);

  void _sample(OutputPulseSnapshot pulse) {
    var changed = false;
    for (final id in channelIds) {
      final active = pulse.frame.channels[id]?['enabled'] == true;
      if (!active && _samples[id]!.isEmpty) continue;
      final next = [
        ..._samples[id]!,
        if (active)
          ...pulse.forChannel(id).samples
        else
          for (var i = 0; i < 4; i++) const PulseSample(10, 0),
      ];
      if (next.length > maxSamples) {
        next.removeRange(0, next.length - maxSamples);
      }
      _samples[id] = List.unmodifiable(next);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    if (_ownsClock) clock.dispose();
    super.dispose();
  }
}
