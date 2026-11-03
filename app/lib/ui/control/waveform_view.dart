import 'package:flutter/material.dart';
import '../../control/models.dart';
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

    final samples = waveform.samples;
    if (samples.isEmpty) return;
    final segmentWidth = size.width / samples.length;
    final unit = segmentWidth / 10;
    final ink = Paint()
      ..color = active ? Palette.yellow : Palette.muted.withValues(alpha: 0.8);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final height = size.height * sample.strength / 100;
      if (height <= 0) continue;
      final x = i * segmentWidth;
      final y = size.height - height;
      if (sample.frequency == 10) {
        canvas.drawRect(Rect.fromLTWH(x, y, segmentWidth + 0.5, height), ink);
      } else {
        final count = sample.frequency <= 0
            ? 0
            : (200 / sample.frequency).ceil();
        if (count == 0) continue;
        final current = count < 4
            ? (i % count == 0 ? 1 : 0)
            : (i.isEven ? count ~/ 2 : (count / 2).ceil());
        if (current == 0) continue;
        final step = (5 / current).floor() * unit;
        for (var j = 0; j < current; j++) {
          canvas.drawRect(
            Rect.fromLTWH(x + j * step, y, 2 * unit, height),
            ink,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) =>
      old.waveform.id != waveform.id || old.active != active;
}
