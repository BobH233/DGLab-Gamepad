import 'waveforms.dart';

export 'waveforms.dart';
export 'touch_control.dart';

const channelIds = ['A', 'B'];
const defaultLinearAmount = 30.0;
const defaultLinearUnit = 'absolute';
const defaultBoostAmount = 30.0;

class ChannelState {
  double base;
  bool enabled;
  String waveform;
  int cursor;
  double linearAmount;
  String linearUnit;
  double boostAmount;
  ChannelState({
    this.base = 0,
    this.enabled = false,
    this.waveform = defaultWaveformId,
    this.cursor = 0,
    this.linearAmount = defaultLinearAmount,
    this.linearUnit = defaultLinearUnit,
    this.boostAmount = defaultBoostAmount,
  });
  ChannelState copy() => ChannelState(
    base: base,
    enabled: enabled,
    waveform: waveform,
    cursor: cursor,
    linearAmount: linearAmount,
    linearUnit: linearUnit,
    boostAmount: boostAmount,
  );
  Map<String, dynamic> toJson() => {
    'base': base,
    'enabled': enabled,
    'waveform': waveform,
    'cursor': cursor,
    'linear': {'amount': linearAmount, 'unit': linearUnit},
    'boost': {'amount': boostAmount},
  };
}

class OutputFrame {
  final int sequence;
  final Map<String, Map<String, dynamic>> channels;
  OutputFrame(this.sequence, Map<String, Map<String, dynamic>> values)
    : channels = Map.unmodifiable(
        values.map((k, v) => MapEntry(k, Map<String, dynamic>.unmodifiable(v))),
      );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'sequence': sequence,
    'channels': channels,
  };
}

abstract interface class OutputSink {
  void accept(OutputFrame frame);
}

class PreviewOutputSink implements OutputSink {
  OutputFrame? latest;
  @override
  void accept(OutputFrame frame) {
    latest = frame;
  }
}

class Binding {
  final String id;
  final String input;
  final String action;
  final Map<String, dynamic> config;
  final bool enabled;
  final double threshold;
  const Binding({
    required this.id,
    required this.input,
    required this.action,
    this.config = const {},
    this.enabled = true,
    this.threshold = 0.55,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'input': input,
    'action': action,
    'config': config,
    'enabled': enabled,
    'threshold': threshold,
  };
  factory Binding.fromJson(Map<String, dynamic> data) => Binding(
    id: data['id'] as String,
    input: data['input'] as String,
    action: data['action'] as String,
    config: _normalizeWaveformConfig(
      Map<String, dynamic>.from(data['config'] as Map),
    ),
    enabled: data['enabled'] as bool? ?? true,
    threshold: ((data['threshold'] as num?)?.toDouble() ?? 0.55).clamp(
      0.15,
      0.95,
    ),
  );
}

class ActionDefinition {
  final String id, name;
  final List<String> inputs;
  final List<Map<String, dynamic>> fields;
  final String source;
  final bool builtin;
  ActionDefinition(
    Map<String, dynamic> data,
    this.source, {
    this.builtin = false,
  }) : id = data['id'] as String,
       name = data['name'] as String,
       inputs = List<String>.from(data['inputs'] as List),
       fields = (data['fields'] as List)
           .map((v) => Map<String, dynamic>.from(v as Map))
           .toList();
  Map<String, dynamic> get defaults => {
    for (final f in fields) f['key'] as String: f['default'],
  };
  Map<String, dynamic> validateConfig(Map<String, dynamic> config) {
    final result = <String, dynamic>{};
    for (final field in fields) {
      final key = field['key'] as String;
      var value = config[key] ?? field['default'];
      switch (field['type']) {
        case 'number':
          if (value is! num ||
              !value.isFinite ||
              value < (field['min'] as num) ||
              value > (field['max'] as num)) {
            throw FormatException('参数 ${field['label']} 超出范围');
          }
        case 'select':
          if (!(field['options'] as List).any((o) => o['value'] == value)) {
            throw FormatException('参数 $key 无效');
          }
        case 'waveform':
          value = canonicalWaveformId(value);
          if (!waveforms.any((w) => w.id == value)) {
            throw const FormatException('波形不存在');
          }
        case 'waveforms':
          if (value is! List ||
              value.isEmpty ||
              value.length > waveforms.length) {
            throw const FormatException('请选择波形列表');
          }
          value = value.map(canonicalWaveformId).toSet().toList();
          if (value.any((v) => !waveforms.any((w) => w.id == v))) {
            throw const FormatException('请选择波形列表');
          }
        default:
          throw FormatException('未知参数类型 ${field['type']}');
      }
      result[key] = value;
    }
    return result;
  }
}

Map<String, dynamic> _normalizeWaveformConfig(Map<String, dynamic> config) {
  final result = Map<String, dynamic>.from(config);
  if (result.containsKey('waveform')) {
    result['waveform'] = canonicalWaveformId(result['waveform']);
  }
  if (result['list'] case final List<dynamic> list) {
    result['list'] = list.map(canonicalWaveformId).toSet().toList();
  }
  return result;
}

const inputLabels = {
  'leftTrigger': 'LT',
  'rightTrigger': 'RT',
  'leftShoulder': 'LB',
  'rightShoulder': 'RB',
  'south': 'A / 南',
  'east': 'B / 东',
  'west': 'X / 西',
  'north': 'Y / 北',
  'up': '方向键 ↑',
  'down': '方向键 ↓',
  'left': '方向键 ←',
  'right': '方向键 →',
  'leftStick': 'L3',
  'rightStick': 'R3',
  'view': 'SELECT',
  'menu': 'START',
  'leftStickVector': '左摇杆',
  'rightStickVector': '右摇杆',
};
String inputKind(String input) => input.endsWith('Vector')
    ? 'stick'
    : input.endsWith('Trigger')
    ? 'trigger'
    : 'button';
