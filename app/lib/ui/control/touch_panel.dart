import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../control/control_desk.dart';
import '../palette.dart';

const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFeatures: [FontFeature.tabularFigures()],
);
const _particleLifetimeMs = 720;
const _particleMaxRadius = 3.6;

Future<void> showTouchPanelDialog(
  BuildContext context,
  ControlDesk desk,
  String channel,
) async {
  desk.openTouchChannel(channel);
  final height = (MediaQuery.sizeOf(context).height - 48)
      .clamp(280.0, 650.0)
      .toDouble();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SizedBox(
          height: height,
          child: TouchPanel(
            desk: desk,
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    ),
  );
  desk.endTouchPoint();
  desk.closeTouchPanel();
}

class TouchPanel extends StatefulWidget {
  final ControlDesk desk;
  final VoidCallback onClose;

  const TouchPanel({super.key, required this.desk, required this.onClose});

  @override
  State<TouchPanel> createState() => _TouchPanelState();
}

class _TouchPanelState extends State<TouchPanel> {
  bool settings = false;

  ControlDesk get desk => widget.desk;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: desk,
    builder: (context, _) {
      final channel = desk.touchChannel;
      return Container(
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.yellow),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '$channel 通道',
                      style: const TextStyle(
                        color: Palette.yellow,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: settings ? '返回触控区域' : '触控设置',
                    onPressed: () {
                      desk.setTouchSurfaceVisible(settings);
                      setState(() => settings = !settings);
                    },
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    color: Palette.yellow,
                  ),
                  IconButton(
                    tooltip: '退出触控面板',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: Palette.yellow,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Palette.line),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: settings
                    ? SingleChildScrollView(
                        key: const ValueKey('touch-settings'),
                        child: _TouchSettings(desk: desk, channel: channel),
                      )
                    : _TouchSurface(
                        key: ValueKey('touch-surface-$channel'),
                        desk: desk,
                        channel: channel,
                        showGrid: desk.engine.state.touchGrid,
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TouchSurface extends StatefulWidget {
  final ControlDesk desk;
  final String channel;
  final bool showGrid;

  const _TouchSurface({
    super.key,
    required this.desk,
    required this.channel,
    required this.showGrid,
  });

  @override
  State<_TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<_TouchSurface>
    with SingleTickerProviderStateMixin {
  final _random = math.Random();
  final List<_Particle> particles = [];
  late final Ticker _ticker;
  int _clockMs = 0;
  int _tickerBaseMs = 0;
  int? _pointer;
  Offset? _lastPoint;
  Offset? _lastGamepadPoint;
  bool _gamepadTrailScheduled = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  void _start() {
    if (_ticker.isActive) return;
    _tickerBaseMs = _clockMs;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    if (!mounted) return;
    _clockMs = _tickerBaseMs + elapsed.inMilliseconds;
    particles.removeWhere(
      (particle) => _clockMs - particle.bornAt >= _particleLifetimeMs,
    );
    if (_pointer == null && particles.isEmpty) {
      _ticker.stop();
    }
    setState(() {});
  }

  void _pointerDown(PointerDownEvent event, Size size) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _lastGamepadPoint = null;
    final point = _clamp(event.localPosition, size);
    _lastPoint = point;
    particles.clear();
    _spawn(point, point, size);
    widget.desk.updateTouchPoint(
      point.dx / size.width,
      point.dy / size.height,
      notify: true,
    );
    _start();
  }

  void _pointerMove(PointerMoveEvent event, Size size) {
    if (_pointer != event.pointer) return;
    final point = _clamp(event.localPosition, size);
    _spawn(_lastPoint ?? point, point, size);
    _lastPoint = point;
    widget.desk.updateTouchPoint(point.dx / size.width, point.dy / size.height);
    _start();
  }

  void _pointerEnd(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _lastPoint = null;
    _lastGamepadPoint = null;
    widget.desk.endTouchPoint();
    _start();
  }

  @override
  void didUpdateWidget(_TouchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleGamepadTrail();
  }

  void _scheduleGamepadTrail() {
    if (_pointer != null) {
      _lastGamepadPoint = null;
      return;
    }
    final point = widget.desk.engine.state.touchPoint;
    if (point == null || !point.active) {
      _lastGamepadPoint = null;
      return;
    }
    final current = Offset(point.x, point.y);
    final previous = _lastGamepadPoint;
    if (previous != null && (current - previous).distance < 0.001) return;
    if (_gamepadTrailScheduled) return;
    _gamepadTrailScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadTrailScheduled = false;
      if (!mounted || _pointer != null) {
        _lastGamepadPoint = null;
        return;
      }
      final latest = widget.desk.engine.state.touchPoint;
      if (latest == null || !latest.active) {
        _lastGamepadPoint = null;
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final size = box.size;
      final to = Offset(latest.x * size.width, latest.y * size.height);
      final from = previous == null
          ? to
          : Offset(previous.dx * size.width, previous.dy * size.height);
      _spawn(from, to, size);
      _lastGamepadPoint = Offset(latest.x, latest.y);
      _start();
    });
  }

  Offset _clamp(Offset value, Size size) =>
      Offset(value.dx.clamp(0.0, size.width), value.dy.clamp(0.0, size.height));

  void _spawn(Offset from, Offset to, Size size) {
    final now = _clockMs;
    final distance = (to - from).distance;
    final count = from == to ? 5 : (distance / 9).ceil().clamp(2, 18);
    for (var i = 0; i < count; i++) {
      final progress = (i + 1) / count;
      final base = Offset.lerp(from, to, progress)!;
      final spread = 2.5 + distance.clamp(0, 80) * 0.035;
      particles.add(
        _Particle(
          position: Offset(
            (base.dx + (_random.nextDouble() - 0.5) * spread).clamp(
              0.0,
              size.width,
            ),
            (base.dy + (_random.nextDouble() - 0.5) * spread).clamp(
              0.0,
              size.height,
            ),
          ),
          bornAt: now,
        ),
      );
    }
    if (particles.length > 180) {
      particles.removeRange(0, particles.length - 180);
    }
  }

  @override
  void dispose() {
    widget.desk.endTouchPoint();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.desk.engine.state;
    final readout = state.touchReadout(widget.channel);
    final point = state.touchPoint;
    final horizontal =
        state.touchHorizontalSplits[widget.channel] ?? const [1 / 3, 2 / 3];
    final vertical =
        state.touchVerticalSplits[widget.channel] ?? const [1 / 3, 2 / 3];
    return SizedBox.expand(
      key: const ValueKey('touch-surface'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _pointerDown(event, size),
              onPointerMove: (event) => _pointerMove(event, size),
              onPointerUp: _pointerEnd,
              onPointerCancel: _pointerEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _TouchPainter(
                        particles: particles,
                        particleCount: particles.length,
                        now: _clockMs,
                        showGrid: widget.showGrid,
                        horizontalSplits: horizontal,
                        verticalSplits: vertical,
                      ),
                    ),
                  ),
                  if (point != null)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 50),
                      curve: Curves.linear,
                      left: (point.x * size.width - 8).clamp(
                        0,
                        math.max(0, size.width - 16),
                      ),
                      top: (point.y * size.height - 8).clamp(
                        0,
                        math.max(0, size.height - 16),
                      ),
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          key: const ValueKey('touch-cursor'),
                          duration: const Duration(milliseconds: 80),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: point.active
                                ? Palette.yellow
                                : Colors.transparent,
                            border: Border.all(
                              color: Palette.yellow.withValues(
                                alpha: point.active ? 1 : 0.45,
                              ),
                              width: 1.5,
                            ),
                            boxShadow: point.active
                                ? [
                                    BoxShadow(
                                      color: Palette.yellow.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 18,
                    bottom: 14,
                    child: Text(
                      readout == null
                          ? '强度 0  ·  频率 --'
                          : '强度 ${readout.intensity.round()}  ·  频率 ${readout.frequencyHz.round()} Hz',
                      style: _mono.copyWith(
                        color: Palette.yellow,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TouchSettings extends StatelessWidget {
  final ControlDesk desk;
  final String channel;

  const _TouchSettings({required this.desk, required this.channel});

  @override
  Widget build(BuildContext context) {
    final state = desk.engine.state;
    final balance = state.touchBalance[channel] ?? 0.5;
    final balanceLevel = 1 + (balance * 14).round();
    final frequencySplits =
        state.touchVerticalSplits[channel] ?? const [1 / 3, 2 / 3];
    final intensitySplits =
        state.touchHorizontalSplits[channel] ?? const [1 / 3, 2 / 3];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '触控功能设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 22, color: Palette.line),
          Row(
            children: [
              const Expanded(child: Text('显示网格与提示')),
              Switch(value: state.touchGrid, onChanged: desk.setTouchGrid),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('触控映射模板')),
              _Pill(label: '智能'),
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(child: Text('频率映射（纵向）')),
              _Pill(label: '三段渐变'),
            ],
          ),
          const SizedBox(height: 12),
          _MappingRangeSlider(
            splits: frequencySplits,
            onChanged: (value) => desk.setTouchVerticalSplits(
              channel,
              value[0],
              value[1],
              persist: false,
            ),
            onEnd: desk.save,
            sliderKey: const ValueKey('frequency-mapping-range'),
            showFrequencyLabels: true,
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(child: Text('强度映射（横向）')),
              _Pill(label: '两侧渐变'),
            ],
          ),
          const SizedBox(height: 10),
          _MappingRangeSlider(
            splits: intensitySplits,
            onChanged: (value) => desk.setTouchHorizontalSplits(
              channel,
              value[0],
              value[1],
              persist: false,
            ),
            onEnd: desk.save,
            sliderKey: const ValueKey('intensity-mapping-range'),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Text('高低频平衡')),
              Text(
                '$balanceLevel',
                style: _mono.copyWith(color: Palette.yellow, fontSize: 13),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              inactiveTrackColor: Palette.line,
              activeTrackColor: Palette.yellow,
              thumbColor: Palette.yellow,
            ),
            child: Slider(
              value: balanceLevel.toDouble(),
              min: 1,
              max: 15,
              divisions: 14,
              onChanged: (value) => desk.setTouchBalance(
                channel,
                (value - 1) / 14,
                persist: false,
              ),
              onChangeEnd: (value) => desk.setTouchBalance(
                channel,
                (value - 1) / 14,
                persist: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: Palette.raised,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Palette.muted, fontSize: 11),
    ),
  );
}

class _MappingRangeSlider extends StatelessWidget {
  final List<double> splits;
  final ValueChanged<List<double>> onChanged;
  final VoidCallback onEnd;
  final Key sliderKey;
  final bool showFrequencyLabels;

  const _MappingRangeSlider({
    required this.splits,
    required this.onChanged,
    required this.onEnd,
    required this.sliderKey,
    this.showFrequencyLabels = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (showFrequencyLabels)
        SizedBox(
          height: 28,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(left: 0, child: _ValueBox('100')),
                Positioned(
                  left: (splits[0] * (constraints.maxWidth - 38)).clamp(
                    38.0,
                    constraints.maxWidth - 76,
                  ),
                  child: const _ValueBox('10'),
                ),
                Positioned(
                  left: (splits[1] * (constraints.maxWidth - 38)).clamp(
                    38.0,
                    constraints.maxWidth - 76,
                  ),
                  child: const _ValueBox('10'),
                ),
                const Positioned(right: 0, child: _ValueBox('100')),
              ],
            ),
          ),
        ),
      SizedBox(
        height: 48,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: Palette.yellow,
            inactiveTrackColor: Palette.line,
            disabledActiveTrackColor: Palette.line,
            disabledInactiveTrackColor: Palette.line,
            thumbColor: Palette.yellow,
            overlayColor: Palette.yellow.withValues(alpha: 0.12),
            rangeTrackShape: const RectangularRangeSliderTrackShape(),
            rangeThumbShape: const _MappingRangeThumbShape(),
          ),
          child: RangeSlider(
            key: sliderKey,
            values: RangeValues(splits[0], splits[1]),
            min: 0,
            max: 1,
            onChanged: (values) => onChanged([values.start, values.end]),
            onChangeEnd: (_) => onEnd(),
          ),
        ),
      ),
    ],
  );
}

class _ValueBox extends StatelessWidget {
  final String value;

  const _ValueBox(this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Palette.background,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Palette.line),
    ),
    child: Text(value, style: _mono.copyWith(fontSize: 12)),
  );
}

class _MappingRangeThumbShape extends RangeSliderThumbShape {
  const _MappingRangeThumbShape();

  static const _size = Size(30, 28);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => _size;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final rect = Rect.fromCenter(
      center: center,
      width: _size.width,
      height: _size.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    final canvas = context.canvas;
    canvas.drawRRect(rrect, Paint()..color = Palette.background);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Palette.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (isPressed ?? false) {
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..color = Palette.yellow.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }
}

class _Particle {
  final Offset position;
  final int bornAt;

  const _Particle({required this.position, required this.bornAt});
}

class _TouchPainter extends CustomPainter {
  final List<_Particle> particles;
  final int particleCount;
  final int now;
  final bool showGrid;
  final List<double> horizontalSplits;
  final List<double> verticalSplits;

  _TouchPainter({
    required this.particles,
    required this.particleCount,
    required this.now,
    required this.showGrid,
    required this.horizontalSplits,
    required this.verticalSplits,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Palette.background;
    canvas.drawRect(Offset.zero & size, background);
    if (showGrid) {
      final grid = Paint()
        ..color = Palette.line.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      for (final split in horizontalSplits) {
        final x = size.width * split;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (final split in verticalSplits) {
        final y = size.height * split;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
    for (final particle in particles) {
      final age = ((now - particle.bornAt) / _particleLifetimeMs).clamp(
        0.0,
        1.0,
      );
      final radius = _particleMaxRadius * (1 - age);
      final opacity = math.pow(1 - age, 1.6).toDouble();
      final glow = Paint()
        ..color = Palette.yellow.withValues(alpha: opacity * 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawCircle(particle.position, radius * 2.8, glow);
      canvas.drawCircle(
        particle.position,
        radius,
        Paint()..color = Palette.yellow.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_TouchPainter oldDelegate) => true;
}
