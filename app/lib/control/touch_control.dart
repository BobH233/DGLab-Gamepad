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
}) {
  final horizontal = (1 - (2 * x.clamp(0.0, 1.0) - 1).abs()).toDouble();
  final vertical = y.clamp(0.0, 1.0);
  final double frequencyMs = vertical <= 1 / 3
      ? 100 + (10 - 100) * vertical * 3
      : vertical >= 2 / 3
      ? 10 + (100 - 10) * (vertical - 2 / 3) * 3
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
