class TouchPoint {
  final double x;
  final double y;
  final bool active;

  const TouchPoint(this.x, this.y, {this.active = true});
}

class TouchReadout {
  final double intensity;
  final double frequencyMs;

  const TouchReadout({required this.intensity, required this.frequencyMs});

  double get frequencyHz => 1000 / frequencyMs;
}

TouchReadout mapTouchPoint({
  required double x,
  required double y,
  required double intensityCeiling,
  double horizontalSplitA = 1 / 3,
  double horizontalSplitB = 2 / 3,
  double verticalSplitA = 1 / 3,
  double verticalSplitB = 2 / 3,
}) {
  final pointX = x.clamp(0.0, 1.0);
  final pointY = y.clamp(0.0, 1.0);
  final horizontalA = horizontalSplitA.clamp(0.12, 0.76);
  final horizontalB = horizontalSplitB.clamp(horizontalA + 0.12, 0.88);
  final verticalA = verticalSplitA.clamp(0.12, 0.76);
  final verticalB = verticalSplitB.clamp(verticalA + 0.12, 0.88);
  final horizontal = pointX <= horizontalA
      ? pointX / horizontalA
      : pointX >= horizontalB
      ? (1 - pointX) / (1 - horizontalB)
      : 1.0;
  final double frequencyMs = pointY <= verticalA
      ? 100 + (10 - 100) * pointY / verticalA
      : pointY >= verticalB
      ? 10 + (100 - 10) * (pointY - verticalB) / (1 - verticalB)
      : 10.0;
  return TouchReadout(
    intensity: intensityCeiling.clamp(0.0, 200.0).toDouble() * horizontal,
    frequencyMs: frequencyMs,
  );
}

int encodeWaveformFrequency(double frequencyMs) {
  final value = frequencyMs.clamp(10.0, 1000.0);
  if (value <= 100) return value.round();
  if (value <= 600) return ((value - 100) / 5 + 100).round();
  return ((value - 600) / 10 + 200).round();
}

int encodeBalance(double value) => (value.clamp(0.0, 1.0) * 255).round();
