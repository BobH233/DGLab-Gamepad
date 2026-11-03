import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gamepad_core/gamepad_core.dart';
import 'palette.dart';

enum GamepadAppearance { direwolf, system }

class GamepadDiagram extends StatelessWidget {
  final GamepadState state;
  final GamepadDevice? device;
  final GamepadAppearance appearance;
  const GamepadDiagram({
    super.key,
    required this.state,
    this.device,
    this.appearance = GamepadAppearance.direwolf,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '手柄实时状态',
    value: Control.values
        .where((c) => !isAxis(c) && state.pressed(c))
        .map((c) => device?.label(c) ?? c.name)
        .join('、'),
    child: AspectRatio(
      aspectRatio: 680 / 410,
      child: CustomPaint(painter: _GamepadPainter(state, device, appearance)),
    ),
  );
}

class _GamepadPainter extends CustomPainter {
  final GamepadState state;
  final GamepadDevice? device;
  final GamepadAppearance appearance;
  _GamepadPainter(this.state, this.device, this.appearance);
  bool get direwolf => appearance == GamepadAppearance.direwolf;
  bool has(Control c) => device?.capabilities.contains(c) ?? false;
  String label(Control c) =>
      device?.label(c) ??
      switch (c) {
        Control.south => 'A',
        Control.east => 'B',
        Control.west => 'X',
        Control.north => 'Y',
        _ => c.name,
      };
  final ink = Paint()..isAntiAlias = true;
  void text(
    Canvas canvas,
    String value,
    Offset at,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w500,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: size,
          color: color,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at - Offset(p.width / 2, p.height / 2));
  }

  void outline(Canvas canvas, Path path, Color color, double width) {
    ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    canvas.drawPath(path, ink);
    ink.style = PaintingStyle.fill;
  }

  void roundRect(Canvas c, Rect r, double radius, Color fill, {Color? border}) {
    final shape = RRect.fromRectAndRadius(r, Radius.circular(radius));
    ink
      ..style = PaintingStyle.fill
      ..color = fill;
    c.drawRRect(shape, ink);
    if (border != null) {
      ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = border;
      c.drawRRect(shape, ink);
      ink.style = PaintingStyle.fill;
    }
  }

  void button(
    Canvas c,
    Control control,
    Offset at,
    double radius, {
    String? caption,
  }) {
    final active = state[control] > 0.1;
    ink.color = active
        ? Palette.yellow
        : direwolf
        ? const Color(0xFFE5E3D7)
        : Palette.background;
    c.drawCircle(at, radius, ink);
    ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = active
          ? Palette.yellow
          : has(control)
          ? const Color(0xFF77715A)
          : Palette.line;
    c.drawCircle(at, radius, ink);
    ink.style = PaintingStyle.fill;
    text(
      c,
      caption ?? label(control),
      at,
      radius > 16 ? 17 : 10,
      active || direwolf
          ? Palette.background
          : has(control)
          ? Palette.yellow
          : Palette.muted,
    );
  }

  void stick(Canvas c, Offset center, Control x, Control y, Control press) {
    ink.color = Palette.background;
    c.drawCircle(center, 49, ink);
    ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = Palette.line;
    c.drawCircle(center, 49, ink);
    c.drawLine(center - const Offset(40, 0), center + const Offset(40, 0), ink);
    c.drawLine(center - const Offset(0, 40), center + const Offset(0, 40), ink);
    ink.style = PaintingStyle.fill;
    final position = center + Offset(state[x], state[y]) * 20;
    final active =
        state[x].abs() + state[y].abs() > 0.01 || state.pressed(press);
    ink.color = state.pressed(press) ? Palette.yellow : Palette.raised;
    c.drawCircle(position, 31, ink);
    ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = active ? Palette.yellow : const Color(0xFF67614C);
    c.drawCircle(position, 31, ink);
    c.drawCircle(position, 25, ink..strokeWidth = 0.6);
    ink.style = PaintingStyle.fill;
    if (direwolf) {
      c.drawCircle(position, 33, ink..color = const Color(0xFF1C75AC));
      c.drawCircle(
        position - const Offset(0, 2),
        28,
        ink..color = const Color(0xFFF2E7C0),
      );
      ink.color = state.pressed(press)
          ? Palette.yellow
          : const Color(0xFF1B92CB);
      c.drawOval(
        Rect.fromCenter(
          center: position + const Offset(0, 8),
          width: 25,
          height: 19,
        ),
        ink,
      );
      for (final (dx, dy, angle) in [
        (-17.0, -6.0, -0.4),
        (-7.0, -16.0, -0.2),
        (7.0, -16.0, 0.2),
        (17.0, -6.0, 0.4),
      ]) {
        c.save();
        c.translate(position.dx + dx, position.dy + dy);
        c.rotate(angle);
        c.drawOval(const Rect.fromLTWH(-4, -5.5, 8, 11), ink);
        c.restore();
      }
      if (active) {
        ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Palette.yellow;
        c.drawCircle(position, 36, ink);
        ink.style = PaintingStyle.fill;
      }
    } else {
      text(
        c,
        press == Control.leftStick ? 'L' : 'R',
        position,
        12,
        state.pressed(press) ? Palette.background : Palette.muted,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 680);
    final genericShape = Path()
      ..moveTo(180, 92)
      ..cubicTo(131, 88, 104, 111, 89, 159)
      ..cubicTo(69, 216, 46, 317, 72, 357)
      ..cubicTo(91, 387, 123, 370, 147, 345)
      ..lineTo(223, 270)
      ..quadraticBezierTo(340, 288, 457, 270)
      ..lineTo(533, 345)
      ..cubicTo(557, 370, 589, 387, 608, 357)
      ..cubicTo(634, 317, 611, 216, 591, 159)
      ..cubicTo(576, 111, 549, 88, 500, 92)
      ..quadraticBezierTo(340, 108, 180, 92)
      ..close();
    final shape = direwolf
        ? (Path()
            ..moveTo(180, 89)
            ..quadraticBezierTo(125, 81, 104, 130)
            ..cubicTo(85, 166, 65, 286, 72, 337)
            ..cubicTo(78, 386, 112, 386, 142, 351)
            ..lineTo(204, 289)
            ..quadraticBezierTo(221, 272, 247, 274)
            ..lineTo(433, 274)
            ..quadraticBezierTo(459, 272, 476, 289)
            ..lineTo(538, 351)
            ..cubicTo(568, 386, 602, 386, 608, 337)
            ..cubicTo(615, 286, 595, 166, 576, 130)
            ..quadraticBezierTo(555, 81, 500, 89)
            ..quadraticBezierTo(340, 103, 180, 89)
            ..close())
        : genericShape;
    canvas.drawShadow(shape, Colors.black.withValues(alpha: 0.65), 12, false);
    ink.color = direwolf ? const Color(0xFFDCDCD4) : Palette.surface;
    if (direwolf) {
      ink.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF2F0E4), Color(0xFFD4D4CC), Color(0xFF9B9D99)],
      ).createShader(const Rect.fromLTWH(60, 90, 560, 290));
    }
    canvas.drawPath(shape, ink);
    ink.shader = null;
    outline(
      canvas,
      shape,
      device == null ? Palette.line : const Color(0xFFB4A474),
      2,
    );
    final seam = Path()
      ..moveTo(105, 220)
      ..quadraticBezierTo(135, 245, 153, 301)
      ..moveTo(575, 220)
      ..quadraticBezierTo(545, 245, 527, 301);
    outline(
      canvas,
      seam,
      direwolf ? const Color(0xFFB1B2AA) : Palette.line,
      1.2,
    );
    if (direwolf) {
      final faceSeam = Path()
        ..moveTo(197, 106)
        ..lineTo(340, 172)
        ..lineTo(483, 106)
        ..moveTo(222, 186)
        ..lineTo(340, 242)
        ..lineTo(458, 186);
      outline(canvas, faceSeam, const Color(0xFFFAF7EB), 1.2);
    }
    for (final (x, trigger, shoulder, t, s) in [
      (162.0, Control.leftTrigger, Control.leftShoulder, 'LT', 'LB'),
      (518.0, Control.rightTrigger, Control.rightShoulder, 'RT', 'RB'),
    ]) {
      roundRect(
        canvas,
        Rect.fromCenter(center: Offset(x, 40), width: 74, height: 40),
        12,
        state[trigger] > 0.05 ? Palette.yellow : Palette.surface,
        border: Palette.line,
      );
      text(
        canvas,
        device?.label(trigger) ?? t,
        Offset(x, 40),
        12,
        state[trigger] > 0.05 ? Palette.background : Palette.yellow,
      );
      roundRect(
        canvas,
        Rect.fromCenter(center: Offset(x, 80), width: 94, height: 23),
        7,
        state.pressed(shoulder) ? Palette.yellow : Palette.raised,
        border: Palette.line,
      );
      text(
        canvas,
        device?.label(shoulder) ?? s,
        Offset(x, 80),
        10,
        state.pressed(shoulder) ? Palette.background : Palette.muted,
      );
    }
    final symmetric = !direwolf && device?.family == 'playstation';
    stick(
      canvas,
      symmetric ? const Offset(253, 254) : const Offset(182, 165),
      Control.leftX,
      Control.leftY,
      Control.leftStick,
    );
    stick(
      canvas,
      const Offset(425, 254),
      Control.rightX,
      Control.rightY,
      Control.rightStick,
    );
    final d = symmetric ? const Offset(182, 165) : const Offset(253, 254);
    ink.color = direwolf ? const Color(0xFFDDDDD2) : Palette.background;
    canvas.drawCircle(d, 45, ink);
    for (final (control, delta, rotation) in [
      (Control.up, const Offset(0, -24), 0.0),
      (Control.right, const Offset(24, 0), math.pi / 2),
      (Control.down, const Offset(0, 24), math.pi),
      (Control.left, const Offset(-24, 0), -math.pi / 2),
    ]) {
      final active = state.pressed(control);
      canvas.save();
      canvas.translate(d.dx + delta.dx, d.dy + delta.dy);
      canvas.rotate(rotation);
      roundRect(
        canvas,
        const Rect.fromLTWH(-12, -13, 24, 27),
        4,
        active
            ? Palette.yellow
            : direwolf
            ? const Color(0xFFE8E7DC)
            : Palette.raised,
        border: active ? Palette.yellow : Palette.line,
      );
      final arrow = Path()
        ..moveTo(-4, 1)
        ..lineTo(0, -4)
        ..lineTo(4, 1);
      outline(canvas, arrow, active ? Palette.background : Palette.muted, 1.4);
      canvas.restore();
    }
    button(canvas, Control.north, const Offset(504, 130), 21);
    button(canvas, Control.west, const Offset(468, 166), 21);
    button(canvas, Control.east, const Offset(540, 166), 21);
    button(canvas, Control.south, const Offset(504, 202), 21);
    if (direwolf) {
      for (final (control, x, angle, caption) in [
        (Control.view, 294.0, 0.48, 'SELECT'),
        (Control.menu, 386.0, -0.48, 'START'),
      ]) {
        canvas.save();
        canvas.translate(x, 166);
        canvas.rotate(angle);
        roundRect(
          canvas,
          const Rect.fromLTWH(-24, -10, 48, 20),
          8,
          state.pressed(control) ? Palette.yellow : const Color(0xFFE7E6DC),
          border: const Color(0xFFAEAEA3),
        );
        text(canvas, caption, Offset.zero, 7, const Color(0xFF696B62));
        canvas.restore();
      }
      roundRect(
        canvas,
        const Rect.fromLTWH(313, 250, 20, 5),
        2,
        const Color(0xFF858D86),
      );
    } else {
      button(canvas, Control.view, const Offset(299, 165), 13, caption: '▱');
      button(canvas, Control.menu, const Offset(381, 165), 13, caption: '≡');
      button(canvas, Control.home, const Offset(340, 123), 15, caption: '●');
    }
    if (has(Control.share)) {
      button(canvas, Control.share, const Offset(340, 204), 12, caption: '↑');
    }
    text(
      canvas,
      direwolf ? '' : 'DG-LAB',
      const Offset(340, 318),
      13,
      const Color(0xFF8C8369),
      weight: FontWeight.w700,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamepadPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.device != device ||
      oldDelegate.appearance != appearance;
}
