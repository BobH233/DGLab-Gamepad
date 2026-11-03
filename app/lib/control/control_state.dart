import 'models.dart';

class ControlState {
  Map<String, ChannelState> channels = {
    for (final id in channelIds) id: ChannelState(),
  };
  String selected = 'A';
  Map<String, Map<String, dynamic>> overlays = {};
  int columns = 3;
  int sequence = 0;
  bool touchMode = false;
  String touchChannel = 'A';
  TouchPoint? touchPoint;
  bool touchGrid = true;
  Map<String, double> touchBalance = {'A': 0.5, 'B': 0.5};

  double offset(String channel) {
    double sum = 0;
    for (final item in overlays.values) {
      if (item['channel'] != channel || item['type'] != 'offset') continue;
      final value = (item['value'] as num).toDouble();
      sum += item['unit'] == 'percent'
          ? channels[channel]!.base * value / 100
          : value;
    }
    return sum;
  }

  bool enabled(String channel) {
    var result = channels[channel]!.enabled;
    for (final item in overlays.values) {
      if (item['channel'] == channel && item['type'] == 'enableOverlay') {
        result = item['value'] as bool;
      }
    }
    return result;
  }

  double effective(String channel) =>
      (channels[channel]!.base + offset(channel)).clamp(0, 200);

  TouchReadout? touchReadout(String channel) {
    final point = touchPoint;
    if (!touchMode ||
        channel != touchChannel ||
        point == null ||
        !point.active) {
      return null;
    }
    return mapTouchPoint(
      x: point.x,
      y: point.y,
      intensityCeiling: channels[channel]!.base,
    );
  }

  OutputFrame frame() => OutputFrame(++sequence, {
    for (final id in channelIds) id: _channelFrame(id),
  });

  Map<String, dynamic> _channelFrame(String id) {
    final touchTarget = touchMode && id == touchChannel;
    final readout = touchTarget ? touchReadout(id) : null;
    final live = touchTarget
        ? readout != null && readout.intensity > 0
        : enabled(id);
    return {
      'intensity': touchTarget
          ? readout?.intensity.round() ?? 0
          : enabled(id)
          ? effective(id).round()
          : 0,
      'enabled': live,
      'waveformId': channels[id]!.waveform,
      if (touchTarget) ...{
        'frequencyMs': readout?.frequencyMs ?? 10.0,
        'waveformIntensity': readout == null ? 0 : 100,
      },
      if (touchMode) 'balance': encodeBalance(touchBalance[id] ?? 0.5),
    };
  }

  Map<String, dynamic> context() => {
    for (final id in channelIds)
      id: {
        ...channels[id]!.toJson(),
        'enabled': touchMode && id == touchChannel
            ? touchReadout(id) != null
            : enabled(id),
        'effective': touchMode && id == touchChannel
            ? touchReadout(id)?.intensity ?? 0
            : effective(id),
      },
  };
  void stop() {
    overlays.clear();
    touchPoint = null;
    for (final channel in channels.values) {
      channel.enabled = false;
    }
  }

  void removeBinding(String id) => overlays.remove(id);

  void apply(String bindingId, List<dynamic> commands) {
    if (commands.length > 16) throw const FormatException('一次操作最多返回 16 条指令');
    final draft = ControlState()
      ..channels = channels.map((k, v) => MapEntry(k, v.copy()))
      ..overlays = Map.from(overlays)
      ..selected = selected
      ..columns = columns
      ..touchMode = touchMode
      ..touchChannel = touchChannel
      ..touchPoint = touchPoint
      ..touchGrid = touchGrid
      ..touchBalance = Map.from(touchBalance);
    for (final command in commands) {
      if (command is! Map) throw const FormatException('指令必须是对象');
      draft._apply(bindingId, Map<String, dynamic>.from(command));
    }
    channels = draft.channels;
    overlays = draft.overlays;
    selected = draft.selected;
    touchPoint = draft.touchPoint;
  }

  void _apply(String bindingId, Map<String, dynamic> command) {
    final type = command['type'];
    if (type == 'clearOverlay') {
      overlays.remove(bindingId);
      return;
    }
    final id = command['channel'];
    if (!channelIds.contains(id)) throw const FormatException('通道必须是 A 或 B');
    final channel = channels[id]!;
    double number(String key, double min, double max) {
      final n = command[key];
      if (n is! num || !n.isFinite || n < min || n > max) {
        throw FormatException('指令参数 $key 无效');
      }
      return n.toDouble();
    }

    switch (type) {
      case 'offset':
        number('value', -200, 200);
        if (!['absolute', 'percent'].contains(command['unit'])) {
          throw const FormatException('未知增减单位');
        }
        overlays[bindingId] = Map.unmodifiable(command);
      case 'enableOverlay':
        if (command['value'] is! bool) throw const FormatException('启停必须是布尔值');
        overlays.remove(bindingId);
        overlays[bindingId] = Map.unmodifiable(command);
      case 'toggleEnabled':
        channel.enabled = !channel.enabled;
      case 'adjustBase':
        channel.base = (channel.base + number('value', -200, 200)).clamp(
          0,
          200,
        );
      case 'setBase':
        channel.base = number('value', 0, 200);
      case 'selectChannel':
        selected = id as String;
      case 'waveform':
        final id = canonicalWaveformId(command['id']);
        if (!waveforms.any((w) => w.id == id)) {
          throw const FormatException('波形不存在');
        }
        channel.waveform = id;
        channel.cursor = waveforms.indexWhere((w) => w.id == channel.waveform);
      case 'applyCursor':
        channel.waveform = waveforms[channel.cursor].id;
      case 'moveCursor':
        final i = channel.cursor;
        switch (command['direction']) {
          case 'up':
            channel.cursor = (i - columns).clamp(0, waveforms.length - 1);
          case 'down':
            channel.cursor = (i + columns).clamp(0, waveforms.length - 1);
          case 'left':
            if (i % columns != 0) channel.cursor--;
          case 'right':
            if (i % columns < columns - 1 && i < waveforms.length - 1) {
              channel.cursor++;
            }
          default:
            throw const FormatException('未知方向');
        }
      default:
        throw FormatException('未知指令 $type');
    }
  }
}
