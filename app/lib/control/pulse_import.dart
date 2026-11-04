import 'dart:convert';
import 'dart:math' as math;

import 'touch_control.dart';
import 'waveforms.dart';

const maxPulseFileBytes = 512 * 1024;
const _pulsePrefix = 'Dungeonlab+pulse:';
const _sectionSeparator = '+section+';
const _pointDurationMs = 100;
const _maxSections = 10;
const _maxControlPoints = 4096;
const _maxOutputSamples = maxImportedWaveformFrames * 4;
final _frequencyValues = <int>[
  for (var value = 10; value <= 50; value++) value,
  for (var value = 52; value <= 80; value += 2) value,
  for (var value = 85; value <= 100; value += 5) value,
  for (var value = 110; value <= 200; value += 10) value,
  233,
  266,
  300,
  333,
  366,
  for (var value = 400; value <= 600; value += 50) value,
  for (var value = 700; value <= 1000; value += 100) value,
];
const _sectionDurationMs = <int>[
  100,
  100,
  100,
  100,
  100,
  200,
  200,
  200,
  300,
  300,
  300,
  400,
  400,
  500,
  500,
  600,
  600,
  700,
  700,
  800,
  900,
  900,
  1000,
  1100,
  1100,
  1200,
  1300,
  1300,
  1400,
  1500,
  1600,
  1600,
  1700,
  1800,
  1900,
  2000,
  2100,
  2100,
  2200,
  2300,
  2400,
  2500,
  2600,
  2700,
  2800,
  2900,
  3000,
  3100,
  3200,
  3300,
  3400,
  3500,
  3600,
  3700,
  3800,
  3900,
  4100,
  4200,
  4300,
  4400,
  4500,
  4600,
  4700,
  4900,
  5000,
  5100,
  5200,
  5400,
  5500,
  5600,
  5700,
  5900,
  6000,
  6100,
  6300,
  6400,
  6500,
  6700,
  6800,
  6900,
  7100,
  7200,
  7400,
  7500,
  7600,
  7800,
  7900,
  8100,
  8200,
  8400,
  8500,
  8700,
  8800,
  9000,
  9100,
  9300,
  9400,
  9600,
  9700,
  9900,
  10000,
];

Waveform parsePulseWaveform(String source, {required String name}) {
  if (utf8.encode(source).length > maxPulseFileBytes) {
    throw const FormatException('波形文件不能超过 512 KB');
  }
  final normalizedName = _validateName(name);
  var text = source;
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  text = text.replaceAll(RegExp(r'[\r\n]'), '').trim();
  if (!text.startsWith(_pulsePrefix)) {
    throw const FormatException('不是 DG-LAB .pulse 文件');
  }
  if (!text.runes.every((rune) => rune >= 0x20 && rune <= 0x7e)) {
    throw const FormatException('波形文件包含无效字符');
  }
  final equals = text.indexOf('=');
  if (equals < 0 || text.indexOf('=', equals + 1) >= 0) {
    throw const FormatException('波形全局设置无效');
  }
  final globalValues = text.substring(_pulsePrefix.length, equals).split(',');
  if (globalValues.length != 3) {
    throw const FormatException('波形全局设置无效');
  }
  final globals = globalValues.map(_parseInteger).toList();
  final restIndex = globals[0];
  final speed = globals[1];
  final balance = globals[2];
  if (restIndex < 0 || restIndex > 100) {
    throw const FormatException('小节间隔超出范围');
  }
  if (speed < 1 || speed > 4) {
    throw const FormatException('播放速度超出范围');
  }
  if (balance < 0 || balance > 100) {
    throw const FormatException('高低频平衡超出范围');
  }

  final sectionTexts = text.substring(equals + 1).split(_sectionSeparator);
  if (sectionTexts.isEmpty || sectionTexts.length > _maxSections) {
    throw const FormatException('波形小节数量超出范围');
  }
  var controlPointCount = 0;
  final sections = <_PulseSection>[];
  for (final sectionText in sectionTexts) {
    final slash = sectionText.indexOf('/');
    if (slash <= 0 ||
        slash != sectionText.lastIndexOf('/') ||
        slash == sectionText.length - 1) {
      throw const FormatException('波形小节格式无效');
    }
    final header = sectionText.substring(0, slash).split(',');
    if (header.length != 5) throw const FormatException('波形小节标题无效');
    final values = header.map(_parseInteger).toList();
    final start = values[0];
    final end = values[1];
    final durationIndex = values[2];
    final frequencyMode = values[3];
    final enabled = values[4];
    if (start < 0 || start >= _frequencyValues.length) {
      throw const FormatException('起始频率索引超出范围');
    }
    if (end < 0 || end >= _frequencyValues.length) {
      throw const FormatException('结束频率索引超出范围');
    }
    if (durationIndex < 0 || durationIndex >= _sectionDurationMs.length) {
      throw const FormatException('小节时长超出范围');
    }
    if (frequencyMode < 1 ||
        frequencyMode > 4 ||
        (enabled != 0 && enabled != 1)) {
      throw const FormatException('波形小节参数无效');
    }
    final pointTexts = sectionText.substring(slash + 1).split(',');
    if (pointTexts.length < 2) {
      throw const FormatException('每个波形小节至少需要两个控制点');
    }
    controlPointCount += pointTexts.length;
    if (controlPointCount > _maxControlPoints) {
      throw const FormatException('波形控制点数量超出限制');
    }
    final points = pointTexts.map(_parsePoint).toList();
    sections.add(
      _PulseSection(
        frequencyStart: start,
        frequencyEnd: end,
        durationIndex: durationIndex,
        frequencyMode: frequencyMode,
        enabled: enabled == 1,
        points: points,
      ),
    );
  }
  final enabledSections = sections.where((section) => section.enabled).toList();
  if (enabledSections.isEmpty) {
    throw const FormatException('波形没有启用的小节');
  }

  final repeatCounts = <_PulseSection, int>{};
  final pointRepeat = speed == 2
      ? 2
      : speed == 4
      ? 1
      : 4;
  var estimatedSamples = 0;
  for (final section in enabledSections) {
    final elementDurationMs = section.points.length * _pointDurationMs;
    final targetDurationMs = _sectionDurationMs[section.durationIndex];
    final repeats = math.max(1, (targetDurationMs / elementDurationMs).ceil());
    repeatCounts[section] = repeats;
    estimatedSamples += section.points.length * repeats * pointRepeat;
    if (estimatedSamples > _maxOutputSamples) {
      throw const FormatException('波形展开后过长');
    }
  }
  final restDurationMs = restIndex == 0
      ? 0
      : ((restIndex - 1) ~/ 10 + 1) * _pointDurationMs;
  estimatedSamples += restDurationMs ~/ _pointDurationMs * 4;
  if (estimatedSamples <= 0 || estimatedSamples > _maxOutputSamples) {
    throw const FormatException('波形展开后过长');
  }

  final samples = <_OutputSample>[];
  for (final section in enabledSections) {
    final repeats = repeatCounts[section]!;
    final count = section.points.length;
    final total = count * repeats;
    final start = _frequencyValues[section.frequencyStart].toDouble();
    final end = _frequencyValues[section.frequencyEnd].toDouble();
    final frequencies = switch (section.frequencyMode) {
      1 => List<double>.filled(total, start),
      2 => _interpolate(start, end, total),
      3 => [
        for (var repeat = 0; repeat < repeats; repeat++)
          ..._interpolate(start, end, count),
      ],
      _ => [
        for (final frequency in _interpolate(start, end, repeats))
          for (var point = 0; point < count; point++) frequency,
      ],
    };
    for (var index = 0; index < total; index++) {
      for (var repeat = 0; repeat < pointRepeat; repeat++) {
        samples.add(
          _OutputSample(
            frequencies[index],
            section.points[index % count].strength,
          ),
        );
      }
    }
  }
  for (var index = 0; index < restDurationMs ~/ _pointDurationMs * 4; index++) {
    samples.add(const _OutputSample(10, 0));
  }
  final frames = _encodeFrames(samples);
  return Waveform(_waveformId(frames), normalizedName, frames, isCustom: true);
}

String pulseNameFromFile(String fileName) {
  final normalized = fileName.replaceAll('\\', '/');
  var name = normalized.substring(normalized.lastIndexOf('/') + 1);
  final extension = name.lastIndexOf('.');
  if (extension > 0) name = name.substring(0, extension);
  name = name.trim();
  if (name.isEmpty) return '自定义波形';
  return String.fromCharCodes(name.runes.take(40));
}

String _validateName(String name) {
  final value = name.trim();
  if (value.isEmpty) throw const FormatException('请输入波形名称');
  if (value.runes.length > 40) {
    throw const FormatException('波形名称不能超过 40 个字符');
  }
  return value;
}

int _parseInteger(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw const FormatException('波形包含无效整数');
  }
  final parsed = int.tryParse(value);
  if (parsed == null) throw const FormatException('波形数字超出范围');
  return parsed;
}

_PulsePoint _parsePoint(String value) {
  if (!RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)-[01]$').hasMatch(value)) {
    throw const FormatException('波形控制点无效');
  }
  final dash = value.lastIndexOf('-');
  final strength = double.tryParse(value.substring(0, dash));
  if (strength == null ||
      !strength.isFinite ||
      strength < 0 ||
      strength > 100) {
    throw const FormatException('波形强度超出范围');
  }
  return _PulsePoint(strength.round());
}

List<double> _interpolate(double start, double end, int count) {
  if (count <= 1) return List<double>.filled(math.max(1, count), start);
  return [
    for (var index = 0; index < count; index++)
      start + (end - start) * index / (count - 1),
  ];
}

List<String> _encodeFrames(List<_OutputSample> samples) {
  final frames = <String>[];
  for (var start = 0; start < samples.length; start += 4) {
    final bytes = <int>[];
    for (var offset = 0; offset < 4; offset++) {
      final sample = start + offset < samples.length
          ? samples[start + offset]
          : const _OutputSample(10, 0);
      bytes.add(encodeWaveformFrequency(sample.frequency));
    }
    for (var offset = 0; offset < 4; offset++) {
      bytes.add(
        start + offset < samples.length ? samples[start + offset].strength : 0,
      );
    }
    frames.add(
      bytes
          .map(
            (value) => value
                .clamp(0, 255)
                .toRadixString(16)
                .padLeft(2, '0')
                .toUpperCase(),
          )
          .join(),
    );
  }
  return frames;
}

String _waveformId(List<String> frames) {
  var hash = 0x811c9dc5;
  for (final codeUnit in frames.join().codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

class _PulsePoint {
  final int strength;
  const _PulsePoint(this.strength);
}

class _PulseSection {
  final int frequencyStart;
  final int frequencyEnd;
  final int durationIndex;
  final int frequencyMode;
  final bool enabled;
  final List<_PulsePoint> points;
  const _PulseSection({
    required this.frequencyStart,
    required this.frequencyEnd,
    required this.durationIndex,
    required this.frequencyMode,
    required this.enabled,
    required this.points,
  });
}

class _OutputSample {
  final double frequency;
  final int strength;
  const _OutputSample(this.frequency, this.strength);
}
