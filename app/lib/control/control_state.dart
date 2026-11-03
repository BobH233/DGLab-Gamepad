import 'models.dart';

enum ControlFocusArea { channel, waveform }

typedef ControlFocusTarget = ({
  ControlFocusArea area,
  String channel,
  int waveformIndex,
});

class ControlState {
  static final _screenTouchOwner = Object();
  Map<String, ChannelState> channels = {
    for (final id in channelIds) id: ChannelState(),
  };
  String selected = 'A';
  Map<String, Map<String, dynamic>> overlays = {};
  int columns = 3;
  int sequence = 0;
  ControlFocusTarget? focusTarget;
  int focusRequest = 0;
  int touchPanelRequest = 0;
  String? touchPanelRequestChannel;
  bool touchMode = false;
  bool touchSurfaceVisible = false;
  String touchChannel = 'A';
  TouchPoint? touchPoint;
  Object? _touchOwner;
  bool touchGrid = true;
  Map<String, double> touchBalance = {'A': 0.5, 'B': 0.5};
  Map<String, List<double>> touchHorizontalSplits = {
    'A': [1 / 3, 2 / 3],
    'B': [1 / 3, 2 / 3],
  };
  Map<String, List<double>> touchVerticalSplits = {
    'A': [1 / 3, 2 / 3],
    'B': [1 / 3, 2 / 3],
  };

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
        !touchSurfaceVisible ||
        channel != touchChannel ||
        point == null ||
        !point.active) {
      return null;
    }
    final horizontal = touchHorizontalSplits[channel] ?? const [1 / 3, 2 / 3];
    final vertical = touchVerticalSplits[channel] ?? const [1 / 3, 2 / 3];
    return mapTouchPoint(
      x: point.x,
      y: point.y,
      intensityCeiling: channels[channel]!.base,
      horizontalSplitA: horizontal[0],
      horizontalSplitB: horizontal[1],
      verticalSplitA: vertical[0],
      verticalSplitB: vertical[1],
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

  Map<String, dynamic> touchContext() => {
    'open': touchMode,
    'surface': touchSurfaceVisible,
    'channel': touchChannel,
    'point': touchPoint == null
        ? null
        : {
            'x': touchPoint!.x,
            'y': touchPoint!.y,
            'active': touchPoint!.active,
          },
  };

  void beginScreenTouch(double x, double y) {
    touchPoint = TouchPoint(x.clamp(0, 1), y.clamp(0, 1));
    _touchOwner = _screenTouchOwner;
  }

  void endScreenTouch() {
    if (!identical(_touchOwner, _screenTouchOwner)) return;
    final point = touchPoint;
    if (point != null) {
      touchPoint = TouchPoint(point.x, point.y, active: false);
    }
    _touchOwner = null;
  }

  void clearTouchPoint() {
    touchPoint = null;
    _touchOwner = null;
  }

  void stop() {
    overlays.clear();
    clearTouchPoint();
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
      ..focusTarget = focusTarget
      ..focusRequest = focusRequest
      ..touchPanelRequest = touchPanelRequest
      ..touchPanelRequestChannel = touchPanelRequestChannel
      ..touchMode = touchMode
      ..touchSurfaceVisible = touchSurfaceVisible
      ..touchChannel = touchChannel
      ..touchPoint = touchPoint
      .._touchOwner = _touchOwner
      ..touchGrid = touchGrid
      ..touchBalance = Map.from(touchBalance)
      ..touchHorizontalSplits = {
        for (final entry in touchHorizontalSplits.entries)
          entry.key: List.from(entry.value),
      }
      ..touchVerticalSplits = {
        for (final entry in touchVerticalSplits.entries)
          entry.key: List.from(entry.value),
      };
    for (final command in commands) {
      if (command is! Map) throw const FormatException('指令必须是对象');
      draft._apply(bindingId, Map<String, dynamic>.from(command));
    }
    channels = draft.channels;
    overlays = draft.overlays;
    selected = draft.selected;
    focusTarget = draft.focusTarget;
    focusRequest = draft.focusRequest;
    touchPanelRequest = draft.touchPanelRequest;
    touchPanelRequestChannel = draft.touchPanelRequestChannel;
    touchPoint = draft.touchPoint;
    _touchOwner = draft._touchOwner;
  }

  void _apply(String bindingId, Map<String, dynamic> command) {
    final type = command['type'];
    if (type == 'clearOverlay') {
      overlays.remove(bindingId);
      return;
    }
    if (type == 'toggleTouchPanel') {
      final id = command['channel'];
      if (!channelIds.contains(id)) {
        throw const FormatException('通道必须是 A 或 B');
      }
      touchPanelRequest++;
      touchPanelRequestChannel = id;
      _focus(id);
      return;
    }
    if (type == 'touchPoint') {
      if (!touchMode ||
          !touchSurfaceVisible ||
          (_touchOwner != null && _touchOwner != bindingId)) {
        return;
      }
      final active = command['active'];
      if (active is! bool) throw const FormatException('触控状态必须是布尔值');
      double value(String key) {
        final number = command[key];
        if (number is! num || !number.isFinite || number < 0 || number > 1) {
          throw FormatException('指令参数 $key 无效');
        }
        return number.toDouble();
      }

      touchPoint = TouchPoint(value('x'), value('y'), active: active);
      _touchOwner = active ? bindingId : null;
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
        _focus(id);
      case 'enableOverlay':
        if (command['value'] is! bool) throw const FormatException('启停必须是布尔值');
        overlays.remove(bindingId);
        overlays[bindingId] = Map.unmodifiable(command);
        _focus(id);
      case 'toggleEnabled':
        channel.enabled = !channel.enabled;
        _focus(id);
      case 'adjustBase':
        channel.base = (channel.base + number('value', -200, 200)).clamp(
          0,
          200,
        );
        _focus(id);
      case 'setBase':
        channel.base = number('value', 0, 200);
        _focus(id);
      case 'selectChannel':
        selected = id;
        _focus(id);
      case 'waveform':
        final waveformId = canonicalWaveformId(command['id']);
        if (!waveforms.any((w) => w.id == waveformId)) {
          throw const FormatException('波形不存在');
        }
        channel.waveform = waveformId;
        channel.cursor = waveforms.indexWhere((w) => w.id == channel.waveform);
        _focus(id, waveformIndex: channel.cursor);
      case 'applyCursor':
        channel.waveform = waveforms[channel.cursor].id;
        _focus(id, waveformIndex: channel.cursor);
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
        _focus(id, waveformIndex: channel.cursor);
      default:
        throw FormatException('未知指令 $type');
    }
  }

  void _focus(String channel, {int? waveformIndex}) {
    focusTarget = (
      area: waveformIndex == null
          ? ControlFocusArea.channel
          : ControlFocusArea.waveform,
      channel: channel,
      waveformIndex: waveformIndex ?? 0,
    );
    focusRequest++;
  }
}
