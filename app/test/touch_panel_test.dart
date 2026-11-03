import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/ui/control/touch_panel.dart';
import 'package:dglab_gamepad/ui/palette.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1160, 800),
  ]) {
    testWidgets('Touch panel is silent until dragging at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = StreamController<Map<String, dynamic>>();
      final monitor = InputMonitor(
        events: events.stream,
        observeLifecycle: false,
      );
      final desk = ControlDesk(monitor);
      desk.engine.state.channels['A']!
        ..base = 120
        ..enabled = true;
      desk.engine.state.channels['B']!
        ..base = 44
        ..enabled = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Palette.background,
          ),
          home: Scaffold(
            body: SafeArea(
              child: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showTouchPanelDialog(context, desk, 'A'),
                      child: const Text('打开 A 触控'),
                    ),
                    TextButton(
                      onPressed: () => showTouchPanelDialog(context, desk, 'B'),
                      child: const Text('打开 B 触控'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开 A 触控'));
      await tester.pumpAndSettle();

      expect(desk.touchOpen, isTrue);
      expect(find.byType(Dialog), findsOneWidget);
      expect(desk.output.latest?.channels['A']!['intensity'], 0);
      expect(desk.output.latest?.channels['B']!['intensity'], 44);

      await tester.tap(find.byTooltip('触控设置'));
      await tester.pumpAndSettle();
      expect(find.text('频率映射（纵向）'), findsOneWidget);
      expect(find.text('强度映射（横向）'), findsOneWidget);
      final balance = tester.widget<Slider>(
        find.descendant(of: find.byType(Dialog), matching: find.byType(Slider)),
      );
      expect(balance.min, 1);
      expect(balance.max, 15);
      final horizontal = desk.engine.state.touchHorizontalSplits['A']!;
      final horizontalBefore = horizontal[0];
      await tester.ensureVisible(
        find.byKey(const ValueKey('intensity-mapping-range')),
      );
      await tester.pumpAndSettle();
      final intensityRange = find.byKey(
        const ValueKey('intensity-mapping-range'),
      );
      final intensityRect = tester.getRect(intensityRange);
      await tester.dragFrom(
        Offset(
          intensityRect.left + intensityRect.width * horizontalBefore,
          intensityRect.center.dy,
        ),
        const Offset(36, 0),
      );
      await tester.pump();
      expect(
        desk.engine.state.touchHorizontalSplits['A']![0],
        greaterThan(horizontalBefore),
      );
      final vertical = desk.engine.state.touchVerticalSplits['A']!;
      final verticalBefore = vertical[0];
      await tester.ensureVisible(
        find.byKey(const ValueKey('frequency-mapping-range')),
      );
      await tester.pumpAndSettle();
      final frequencyRange = find.byKey(
        const ValueKey('frequency-mapping-range'),
      );
      final frequencyRect = tester.getRect(frequencyRange);
      await tester.dragFrom(
        Offset(
          frequencyRect.left + frequencyRect.width * verticalBefore,
          frequencyRect.center.dy,
        ),
        const Offset(36, 0),
      );
      await tester.pump();
      expect(
        desk.engine.state.touchVerticalSplits['A']![0],
        greaterThan(verticalBefore),
      );
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(desk.engine.state.touchGrid, isFalse);
      await tester.ensureVisible(find.byTooltip('返回触控区域'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回触控区域'));
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('touch-surface'));
      final rect = tester.getRect(surface);
      final gesture = await tester.startGesture(rect.center);
      await tester.pump();
      expect(desk.engine.state.touchReadout('A')!.intensity, closeTo(120, 1));
      expect(desk.output.latest?.channels['A']!['enabled'], true);
      expect(desk.output.latest?.channels['B']!['intensity'], 44);

      final leftSplit = desk.engine.state.touchHorizontalSplits['A']![0];
      await gesture.moveTo(
        Offset(rect.left + rect.width * leftSplit / 2, rect.center.dy),
      );
      await tester.pump();
      expect(desk.engine.state.touchReadout('A')!.intensity, closeTo(60, 1));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(desk.output.latest?.channels['A']!['intensity'], 0);
      expect(desk.output.latest?.channels['A']!['enabled'], false);

      await tester.tap(find.byTooltip('退出触控面板'));
      await tester.pumpAndSettle();
      expect(desk.touchOpen, isFalse);
      expect(desk.output.latest?.channels['A']!['intensity'], 120);
      expect(desk.output.latest?.channels['B']!['intensity'], 44);

      await tester.tap(find.text('打开 B 触控'));
      await tester.pumpAndSettle();
      expect(desk.touchChannel, 'B');
      expect(desk.engine.state.selected, 'B');
      expect(desk.output.latest?.channels['A']!['intensity'], 120);
      expect(desk.output.latest?.channels['B']!['intensity'], 0);
      await tester.tap(find.byTooltip('退出触控面板'));
      await tester.pumpAndSettle();
      expect(desk.touchOpen, isFalse);
      expect(find.byType(Dialog), findsNothing);
      expect(desk.output.latest?.channels['A']!['intensity'], 120);
      expect(desk.output.latest?.channels['B']!['intensity'], 44);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      desk.dispose();
      monitor.dispose();
      unawaited(events.close());
    });
  }
}
