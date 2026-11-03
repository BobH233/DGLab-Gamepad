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
  Widget build(BuildContext context) {
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
                  onPressed: () => setState(() => settings = !settings),
                  icon: Icon(
                    settings ? Icons.close_rounded : Icons.settings_outlined,
                    size: 20,
                  ),
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
                      child: _TouchSettings(
                        desk: desk,
                        channel: channel,
                        onClose: () => setState(() => settings = false),
                      ),
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
  }
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
    particles.removeWhere((particle) => _clockMs >= particle.expiresAt);
    if (_pointer == null && particles.isEmpty) {
      _ticker.stop();
    }
    setState(() {});
  }

  void _pointerDown(PointerDownEvent event, Size size) {
    if (_pointer != null) return;
    _pointer = event.pointer;
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
    widget.desk.endTouchPoint();
    _start();
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
          radius: 1.4 + _random.nextDouble() * 2.8,
          bornAt: now,
          expiresAt: now + 420 + _random.nextInt(420),
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
                        now: _clockMs,
                        showGrid: widget.showGrid,
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
  final VoidCallback onClose;

  const _TouchSettings({
    required this.desk,
    required this.channel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final state = desk.engine.state;
    final balance = state.touchBalance[channel] ?? 0.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '关闭触控设置',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: Palette.yellow,
              ),
              const Expanded(
                child: Text(
                  '触控功能设置',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 48),
            ],
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
          _FrequencyMapping(),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(child: Text('强度映射（横向）')),
              _Pill(label: '两侧渐变'),
            ],
          ),
          const SizedBox(height: 10),
          const _IntensityMapping(),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Text('高低频平衡')),
              Text(
                '${(balance * 30).round()}',
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
              value: balance * 30,
              min: 0,
              max: 30,
              divisions: 30,
              onChanged: (value) =>
                  desk.setTouchBalance(channel, value / 30, persist: false),
              onChangeEnd: (value) =>
                  desk.setTouchBalance(channel, value / 30, persist: true),
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

class _FrequencyMapping extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 24,
          right: 24,
          child: Container(height: 1, color: Palette.line),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ValueBox('100'),
            _ValueBox('10'),
            _ValueBox('10'),
            _ValueBox('100'),
          ],
        ),
      ],
    ),
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

class _IntensityMapping extends StatelessWidget {
  const _IntensityMapping();

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    decoration: BoxDecoration(
      border: Border.all(color: Palette.line),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        for (final weight in [1, 2, 4, 2, 1])
          Expanded(
            flex: weight,
            child: Container(
              margin: const EdgeInsets.all(1),
              color: Palette.yellow.withValues(
                alpha: weight == 4
                    ? 0.9
                    : weight == 2
                    ? 0.42
                    : 0.12,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Particle {
  final Offset position;
  final double radius;
  final int bornAt;
  final int expiresAt;

  const _Particle({
    required this.position,
    required this.radius,
    required this.bornAt,
    required this.expiresAt,
  });
}

class _TouchPainter extends CustomPainter {
  final List<_Particle> particles;
  final int now;
  final bool showGrid;

  _TouchPainter({
    required this.particles,
    required this.now,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Palette.background;
    canvas.drawRect(Offset.zero & size, background);
    if (showGrid) {
      final grid = Paint()
        ..color = Palette.line.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        final x = size.width * i / 3;
        final y = size.height * i / 3;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
    for (final particle in particles) {
      final age =
          ((now - particle.bornAt) /
                  math.max(1, particle.expiresAt - particle.bornAt))
              .clamp(0.0, 1.0);
      final opacity = math.pow(1 - age, 1.6).toDouble();
      final glow = Paint()
        ..color = Palette.yellow.withValues(alpha: opacity * 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawCircle(particle.position, particle.radius * 2.8, glow);
      canvas.drawCircle(
        particle.position,
        particle.radius,
        Paint()..color = Palette.yellow.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_TouchPainter oldDelegate) => true;
}
