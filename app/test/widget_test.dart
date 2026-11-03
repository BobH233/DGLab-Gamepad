import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/ui/monitor_screen.dart';

Map<String, dynamic> packet(Map<String, double> values) => {
  'version': 1,
  'type': 'snapshot',
  'devices': [
    {
      'id': 'test',
      'name': 'Xbox Test',
      'family': 'xbox',
      'transport': 'Test',
      'capabilities': [
        'south',
        'leftX',
        'leftY',
        'rightX',
        'rightY',
        'leftTrigger',
        'rightTrigger',
      ],
      'values': values,
    },
  ],
};

void main() {
  testWidgets('Monitor back button returns to the previous screen', (
    tester,
  ) async {
    final stream = StreamController<Map<String, dynamic>>();
    final monitor = InputMonitor(
      events: stream.stream,
      observeLifecycle: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MonitorScreen(monitor: monitor),
              ),
            ),
            child: const Text('打开监测'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开监测'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回控制台'), findsOneWidget);
    await tester.tap(find.byTooltip('返回控制台'));
    await tester.pumpAndSettle();
    expect(find.text('打开监测'), findsOneWidget);
    expect(tester.takeException(), isNull);
    monitor.dispose();
    unawaited(stream.close());
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(390, 844),
    const Size(1160, 800),
    const Size(320, 640),
  ]) {
    testWidgets('Monitor fits $size and receives native packets', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stream = StreamController<Map<String, dynamic>>();
      final monitor = InputMonitor(
        events: stream.stream,
        observeLifecycle: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MonitorScreen(monitor: monitor),
        ),
      );
      expect(find.text('等待手柄连接'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      stream.add(packet({}));
      await tester.pump();
      await tester.pump();
      expect(find.text('Xbox Test'), findsOneWidget);
      expect(find.text('实时接收'), findsOneWidget);
      stream.add(packet({'south': 1, 'leftTrigger': 0.65}));
      await tester.pump();
      await tester.pump();
      expect(find.text('65%'), findsOneWidget);
      expect(monitor.history.first['values'], containsPair('south', 1.0));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('暂停监测'));
      await tester.pump();
      expect(find.text('已暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('继续监测'));
      await tester.pump();
      final scrollable = find.byType(Scrollable);
      await tester.drag(find.byType(ListView), const Offset(0, -320));
      await tester.pump();
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(offset, greaterThan(0));
      stream.add(packet({'south': 0, 'leftTrigger': 0.4}));
      await tester.pump();
      await tester.pump();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        closeTo(offset, 0.1),
      );
      await tester.ensureVisible(find.text('输入记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('输入记录'));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsOneWidget);
      expect(find.textContaining('leftTrigger'), findsWidgets);
      expect(tester.takeException(), isNull);
      monitor.dispose();
      unawaited(stream.close());
      await tester.pumpWidget(const SizedBox());
    });
  }
}
