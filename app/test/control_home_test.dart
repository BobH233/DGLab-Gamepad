import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/coyote/coyote_controller.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/control/control_store.dart';
import 'package:dglab_gamepad/ui/control/control_home.dart';
import 'package:dglab_gamepad/ui/palette.dart';

void main() {
  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(1160, 800), 1.0),
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.5),
  ]) {
    testWidgets('Control desk fits $size text $scale; bindings persist', (
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
      final coyote = _FakeCoyote();
      final desk = ControlDesk(monitor, coyote: coyote);
      final storage = _MemoryStore();
      await desk.initialize(storage: storage, assets: _LocalAssets());
      expect(desk.ready, isTrue, reason: desk.error);
      var idleNotifications = 0;
      void countIdleNotifications() => idleNotifications++;
      desk.addListener(countIdleNotifications);
      await tester.pump(const Duration(milliseconds: 500));
      expect(idleNotifications, 0);
      desk.removeListener(countIdleNotifications);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Palette.background,
            colorScheme: const ColorScheme.dark(
              primary: Palette.yellow,
              surface: Palette.surface,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ControlHome(desk: desk),
        ),
      );
      expect(find.text('A 通道'), findsWidgets);
      expect(find.text('快捷操作'), findsNothing);
      expect(find.text('应用选中'), findsNothing);
      expect(find.byTooltip('打开 A 通道触控'), findsOneWidget);
      expect(find.byTooltip('打开 B 通道触控'), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(Scrollable), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SliderTheme &&
              widget.data.inactiveTrackColor == Palette.line,
        ),
        findsNWidgets(2),
      );
      final slider = find.byType(Slider).first;
      expect(
        tester.widget<Slider>(slider).allowedInteraction,
        SliderInteraction.slideThumb,
      );
      desk.setBase('A', 100, persist: false);
      await tester.pump();
      final sliderRect = tester.getRect(slider);
      await tester.tapAt(
        Offset(sliderRect.left + sliderRect.width * 0.8, sliderRect.center.dy),
      );
      await tester.pump();
      expect(desk.engine.state.channels['A']!.base, 100);
      await tester.dragFrom(sliderRect.center, const Offset(30, 0));
      await tester.pump();
      expect(desk.engine.state.channels['A']!.base, greaterThan(100));
      desk.setBase('A', 0, persist: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('连接郊狼').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('郊狼 3'), findsOneWidget);
      expect(coyote.scanCount, 1);
      expect(find.text('扫描中'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('增加 A 通道强度'));
      await desk.save();
      await tester.pump();
      expect(desk.engine.state.channels['A']!.base, 1);
      final plus = find.byTooltip('增加 A 通道强度');
      final cardInk = tester.widget<InkWell>(
        find.ancestor(of: plus, matching: find.byType(InkWell)).first,
      );
      expect(cardInk.overlayColor?.resolve({}), Colors.transparent);
      final hold = await tester.startGesture(tester.getCenter(plus));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 240));
      expect(desk.engine.state.channels['A']!.base, greaterThan(1));
      await hold.up();
      await tester.pump();
      final heldValue = desk.engine.state.channels['A']!.base;
      await tester.pump(const Duration(milliseconds: 240));
      expect(desk.engine.state.channels['A']!.base, heldValue);
      final bPlus = find.byTooltip('增加 B 通道强度');
      await tester.ensureVisible(bPlus);
      await tester.pumpAndSettle();
      await tester.tap(bPlus);
      await tester.pump();
      expect(desk.engine.state.selected, 'A');
      await tester.ensureVisible(find.byTooltip('启动 A 通道'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('启动 A 通道'));
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isTrue);
      await tester.tap(find.text('全部停止'));
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isFalse);
      expect(desk.engine.state.channels['A']!.base, heldValue);
      await tester.ensureVisible(find.text('B 通道').first);
      await tester.tap(find.text('B 通道').first);
      await tester.pump();
      expect(desk.engine.state.selected, 'B');
      final scroll = find.byType(ListView).first;
      await tester.drag(scroll, const Offset(0, -650));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('按键绑定').last);
      await tester.pump();
      expect(desk.editing, isTrue);
      await tester.tap(find.text('LT').first);
      await tester.pumpAndSettle();
      expect(find.text('LT · 操作绑定'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.tap(find.text('保存'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(
        desk.bindings
            .firstWhere((b) => b.input == 'leftTrigger')
            .config['amount'],
        50,
      );
      final saved = await storage.read();
      expect(
        (saved!['bindings'] as List)
            .where((b) => b['input'] == 'leftTrigger')
            .first['config']['amount'],
        50,
      );
      await tester.tap(find.text('恢复默认'));
      await tester.pump();
      expect(
        desk.bindings
            .firstWhere((b) => b.input == 'leftTrigger')
            .config['amount'],
        30,
      );
      final resetSaved = await storage.read();
      expect(
        (resetSaved!['bindings'] as List)
            .where((b) => b['input'] == 'leftTrigger')
            .first['config']['amount'],
        30,
      );
      await tester.tap(find.text('操作脚本').last);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      desk.dispose();
      monitor.dispose();
      unawaited(stream.close());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    });
  }

  testWidgets('Touch movement refreshes the preview at 30 FPS', (tester) async {
    final stream = StreamController<Map<String, dynamic>>();
    final monitor = InputMonitor(
      events: stream.stream,
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor, coyote: _FakeCoyote());
    await desk.initialize(storage: _MemoryStore(), assets: _LocalAssets());
    desk.engine.state.channels['A']!.base = 120;
    desk.openTouchChannel('A');
    var notifications = 0;
    void countNotifications() => notifications++;
    desk.addListener(countNotifications);

    desk.updateTouchPoint(0.5, 0.5);
    desk.updateTouchPoint(0.6, 0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(notifications, 0);
    await tester.pump(const Duration(milliseconds: 17));
    expect(notifications, 1);

    desk.updateTouchPoint(0.7, 0.5);
    desk.updateTouchPoint(0.8, 0.5);
    await tester.pump(const Duration(milliseconds: 33));
    expect(notifications, 2);

    desk.removeListener(countNotifications);
    desk.dispose();
    monitor.dispose();
    unawaited(stream.close());
    await tester.pump();
  });

  testWidgets('Hiding touch settings clears and flushes the output', (
    tester,
  ) async {
    final stream = StreamController<Map<String, dynamic>>();
    final monitor = InputMonitor(
      events: stream.stream,
      observeLifecycle: false,
    );
    final coyote = _FakeCoyote();
    final desk = ControlDesk(monitor, coyote: coyote);
    await desk.initialize(storage: _MemoryStore(), assets: _LocalAssets());
    desk.engine.state.channels['A']!.base = 120;
    desk.openTouchChannel('A');
    desk.updateTouchPoint(0.5, 0.5, notify: true);
    expect(desk.engine.state.touchReadout('A'), isNotNull);
    final flushes = coyote.flushes;

    desk.setTouchSurfaceVisible(false);
    expect(desk.engine.state.touchReadout('A'), isNull);
    expect(desk.engine.state.touchPoint, isNull);
    expect(coyote.flushes, flushes + 1);
    desk.updateTouchPoint(0.7, 0.7);
    expect(desk.engine.state.touchPoint, isNull);

    desk.dispose();
    monitor.dispose();
    unawaited(stream.close());
    await tester.pump();
  });

  testWidgets('Y toggles the selected channel touch panel', (tester) async {
    final stream = StreamController<Map<String, dynamic>>();
    final monitor = InputMonitor(
      events: stream.stream,
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor, coyote: _FakeCoyote());
    await desk.initialize(storage: _MemoryStore(), assets: _LocalAssets());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Palette.background,
          colorScheme: const ColorScheme.dark(
            primary: Palette.yellow,
            surface: Palette.surface,
          ),
        ),
        home: ControlHome(desk: desk),
      ),
    );
    desk.selectChannel('B');
    Map<String, dynamic> snapshot(Map<String, double> values) => {
      'version': 1,
      'type': 'snapshot',
      'devices': [
        {
          'id': 'pad',
          'name': 'Pad',
          'family': 'xbox',
          'transport': 'usb',
          'capabilities': ['north'],
          'values': values,
        },
      ],
    };

    stream.add(snapshot({}));
    await tester.pump();
    stream.add(snapshot({'north': 1}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(desk.touchOpen, isTrue);
    expect(desk.touchChannel, 'B');
    expect(find.byType(Dialog), findsOneWidget);

    stream.add(snapshot({}));
    stream.add(snapshot({'north': 1}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(desk.touchOpen, isFalse);

    stream.add(snapshot({}));
    stream.add(snapshot({'north': 1}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(desk.touchOpen, isTrue);

    await tester.tap(find.byTooltip('退出触控面板'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    desk.dispose();
    monitor.dispose();
    unawaited(stream.close());
    await tester.pump();
  });
}

class _LocalAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

class _MemoryStore extends ControlStore {
  Map<String, dynamic>? value;
  _MemoryStore() : super(File('unused'));
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> save(Map<String, dynamic> data) async {
    value = data;
  }
}

class _FakeCoyote extends CoyoteController {
  int scanCount = 0;
  int flushes = 0;

  @override
  Future<void> scan() async {
    scanCount++;
    status = CoyoteStatus.scanning;
    notifyListeners();
  }

  @override
  void flushLatest() {
    flushes++;
  }
}
