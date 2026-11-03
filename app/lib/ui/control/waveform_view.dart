import 'package:flutter/material.dart';
import '../../control/models.dart';
import '../../control/output_waveform_trace.dart';
import '../palette.dart';

class WaveformView extends StatelessWidget {
  final Waveform waveform;
  final bool active;
  const WaveformView({super.key, required this.waveform, this.active = true});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PulsePainter(waveform, active));
}

class _PulsePainter extends CustomPainter {
  final Waveform waveform;
  final bool active;
  _PulsePainter(this.waveform, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    final samples = waveform.samples;
    if (samples.isEmpty) return;
    final segmentWidth = size.width / samples.length;
    final ink = Paint()
      ..color = active ? Palette.yellow : Palette.muted.withValues(alpha: 0.8);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < samples.length; i++) {
      _drawPulseSample(
        canvas,
        sample: samples[i],
        x: i * segmentWidth,
        segmentWidth: segmentWidth,
        height: size.height,
        ink: ink,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) =>
      old.waveform.id != waveform.id || old.active != active;
}

class LiveWaveformView extends StatefulWidget {
  final Waveform waveform;
  final String channel;
  final OutputWaveformTrace trace;
  final bool active;

  const LiveWaveformView({
    super.key,
    required this.waveform,
    required this.channel,
    required this.trace,
    required this.active,
  });

  @override
  State<LiveWaveformView> createState() => _LiveWaveformViewState();
}

class _LiveWaveformViewState extends State<LiveWaveformView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = AnimationController(
      vsync: this,
      duration: OutputWaveformTrace.sampleInterval,
      value: 1,
    );
    widget.trace.addListener(_handleTrace);
  }

  @override
  void didUpdateWidget(covariant LiveWaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trace != widget.trace) {
      oldWidget.trace.removeListener(_handleTrace);
      widget.trace.addListener(_handleTrace);
    }
    if (!widget.active) {
      _scroll.stop();
    } else if (!oldWidget.active) {
      _scroll.value = 1;
    }
  }

  void _handleTrace() {
    if (!mounted || !widget.active) return;
    _scroll.forward(from: 0);
  }

  @override
  void dispose() {
    widget.trace.removeListener(_handleTrace);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return WaveformView(waveform: widget.waveform, active: false);
    }
    return CustomPaint(
      painter: _LivePulsePainter(
        waveform: widget.waveform,
        channel: widget.channel,
        trace: widget.trace,
        scroll: _scroll,
        repaint: Listenable.merge([_scroll, widget.trace]),
      ),
    );
  }
}

class _LivePulsePainter extends CustomPainter {
  static const _sampleSpacing = 5.0;

  final Waveform waveform;
  final String channel;
  final OutputWaveformTrace trace;
  final Animation<double> scroll;

  _LivePulsePainter({
    required this.waveform,
    required this.channel,
    required this.trace,
    required this.scroll,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    final samples = trace.samplesFor(channel);
    if (samples.isEmpty) {
      _drawSamples(canvas, size, waveform.samples, Palette.yellow);
      return;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final entering = samples.length > 4
        ? (1 - scroll.value) * 4 * _sampleSpacing
        : 0.0;
    for (var i = 0; i < samples.length; i++) {
      final x =
          size.width - (samples.length - 1 - i) * _sampleSpacing + entering;
      if (x < -_sampleSpacing || x > size.width) continue;
      _drawPulseSample(
        canvas,
        sample: samples[i],
        x: x,
        segmentWidth: _sampleSpacing,
        height: size.height,
        ink: Paint()
          ..color = Palette.yellow.withValues(
            alpha: (0.28 + 0.72 * i / samples.length).clamp(0.28, 1.0),
          ),
      );
    }
    final fade = Paint()
      ..shader = const LinearGradient(
        colors: [Palette.surface, Color(0x001C1C1B)],
      ).createShader(Rect.fromLTWH(0, 0, size.width * 0.14, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.14, size.height), fade);
    final rightFade = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Palette.surface, Color(0x001C1C1B)],
          ).createShader(
            Rect.fromLTWH(size.width * 0.86, 0, size.width * 0.14, size.height),
          );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.86, 0, size.width * 0.14, size.height),
      rightFade,
    );
    canvas.restore();
  }

  void _drawSamples(
    Canvas canvas,
    Size size,
    List<PulseSample> samples,
    Color color,
  ) {
    if (samples.isEmpty) return;
    final segmentWidth = size.width / samples.length;
    final ink = Paint()..color = color;
    for (var i = 0; i < samples.length; i++) {
      _drawPulseSample(
        canvas,
        sample: samples[i],
        x: i * segmentWidth,
        segmentWidth: segmentWidth,
        height: size.height,
        ink: ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LivePulsePainter old) =>
      old.waveform.id != waveform.id || old.channel != channel;
}

void _drawGrid(Canvas canvas, Size size) {
  final grid = Paint()
    ..color = Palette.line
    ..strokeWidth = 0.6;
  for (var i = 1; i < 4; i++) {
    canvas.drawLine(
      Offset(0, size.height * i / 4),
      Offset(size.width, size.height * i / 4),
      grid,
    );
  }
}

void _drawPulseSample(
  Canvas canvas, {
  required PulseSample sample,
  required double x,
  required double segmentWidth,
  required double height,
  required Paint ink,
}) {
  if (sample.strength <= 0 || sample.frequency <= 0) return;
  final pulseHeight = height * sample.strength / 100;
  final y = height - pulseHeight;
  final count = (200 / sample.frequency).ceil().clamp(1, 10);
  if (count <= 0) return;
  final step = segmentWidth / count;
  final barWidth = step * 0.62;
  for (var i = 0; i < count; i++) {
    canvas.drawRect(Rect.fromLTWH(x + i * step, y, barWidth, pulseHeight), ink);
  }
}
