import 'package:flutter/material.dart';
import 'input/input_monitor.dart';
import 'control/control_desk.dart';
import 'ui/control/control_home.dart';
import 'ui/palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GamepadApp());
}

class GamepadApp extends StatefulWidget {
  const GamepadApp({super.key});
  @override
  State<GamepadApp> createState() => _GamepadAppState();
}

class _GamepadAppState extends State<GamepadApp> {
  late final InputMonitor monitor = InputMonitor();
  late final ControlDesk desk = ControlDesk(monitor);
  @override
  void initState() {
    super.initState();
    desk.initialize();
  }

  @override
  void dispose() {
    desk.dispose();
    monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DG-LAB · 控制台',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Palette.background,
      colorScheme: const ColorScheme.dark(
        primary: Palette.yellow,
        onPrimary: Palette.background,
        surface: Palette.surface,
        onSurface: Palette.text,
        secondary: Palette.yellow,
      ),
      fontFamily: 'PingFang SC',
      dividerColor: Palette.line,
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    ),
    home: ControlHome(desk: desk),
  );
}
