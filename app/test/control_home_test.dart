import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad_core/gamepad_core.dart';
import 'package:dglab_gamepad/coyote/coyote_controller.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/control/control_state.dart';
import 'package:dglab_gamepad/control/control_store.dart';
import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/ui/control/control_home.dart';
import 'package:dglab_gamepad/ui/control/waveform_view.dart';
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
      final textScaler = MediaQuery.textScalerOf(
        tester.element(find.text('A 通道').first),
      );
      expect(textScaler.scale(20), 20);
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
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 100);
      final sliderRect = tester.getRect(slider);
      await tester.tapAt(
        Offset(sliderRect.left + sliderRect.width * 0.8, sliderRect.center.dy),
      );
      await tester.pump();
      expect(desk.engine.state.channels['A']!.base, 100);
      await tester.timedDrag(
        slider,
        const Offset(40, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();
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
      expect(coyote.connected, isFalse);
      await tester.pump(const Duration(milliseconds: 120));
      expect(desk.waveformTrace.samplesFor('A'), isNotEmpty);
      await tester.tap(
        find.text('全部停止').evaluate().isEmpty
            ? find.byTooltip('全部停止')
            : find.text('全部停止'),
      );
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isFalse);
      expect(desk.engine.state.channels['A']!.base, heldValue);
      final startAll = find.text('全部启动').evaluate().isEmpty
          ? find.byTooltip('全部启动')
          : find.text('全部启动');
      expect(startAll, findsOneWidget);
      await tester.tap(startAll);
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isTrue);
      expect(desk.engine.state.enabled('B'), isTrue);
      final stopAll = find.text('全部停止').evaluate().isEmpty
          ? find.byTooltip('全部停止')
          : find.text('全部停止');
      expect(stopAll, findsOneWidget);
      await tester.tap(stopAll);
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isFalse);
      expect(desk.engine.state.enabled('B'), isFalse);
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
      expect(find.text('满行程增减量'), findsNothing);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>).at(1),
          )
          .onChanged!('B');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(
        desk.bindings
            .firstWhere((b) => b.input == 'leftTrigger')
            .config['target'],
        'B',
      );
      final saved = await storage.read();
      expect(
        (saved!['bindings'] as List)
            .where((b) => b['input'] == 'leftTrigger')
            .first['config']['target'],
        'B',
      );
      await tester.tap(find.text('恢复默认'));
      await tester.pump();
      expect(
        desk.bindings
            .firstWhere((b) => b.input == 'leftTrigger')
            .config['target'],
        'A',
      );
      final resetSaved = await storage.read();
      expect(
        (resetSaved!['bindings'] as List)
            .where((b) => b['input'] == 'leftTrigger')
            .first['config']['target'],
        'A',
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

  testWidgets('compact landscape fits both complete channel cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    final rail = find.byKey(const ValueKey('compact-side-navigation'));
    expect(rail, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final railRect = tester.getRect(rail);
    expect(railRect.width, lessThanOrEqualTo(66));
    expect(railRect.height, lessThan(200));
    expect(tester.getSize(find.byType(LiveWaveformView).first).height, 58);
    final dashboard = find.byType(ListView).first;
    final viewport = tester.getRect(dashboard);
    for (final channel in channelIds) {
      final card = find
          .ancestor(
            of: find.text('$channel 通道').first,
            matching: find.byType(Material),
          )
          .first;
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(rect.right, lessThanOrEqualTo(railRect.left));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    desk.dispose();
    monitor.dispose();
    unawaited(stream.close());
    await tester.pump();
  });

  testWidgets('temporary label edits independent channel controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stream = StreamController<Map<String, dynamic>>();
    final monitor = InputMonitor(
      events: stream.stream,
      observeLifecycle: false,
    );
    final storage = _MemoryStore();
    final desk = ControlDesk(monitor, coyote: _FakeCoyote());
    await desk.initialize(storage: storage, assets: _LocalAssets());
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

    await tester.tap(find.byTooltip('编辑 A 通道控制参数'));
    await tester.pumpAndSettle();
    expect(find.text('A 通道控制参数'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('linear-unit-A')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('基础强度百分比').last);
    await tester.enterText(find.byKey(const ValueKey('linear-amount-A')), '80');
    await tester.enterText(find.byKey(const ValueKey('boost-amount-A')), '45');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(desk.engine.state.channels['A']!.linearAmount, 80);
    expect(desk.engine.state.channels['A']!.linearUnit, 'percent');
    expect(desk.engine.state.channels['A']!.boostAmount, 45);

    await tester.ensureVisible(find.byTooltip('编辑 B 通道控制参数'));
    await tester.tap(find.byTooltip('编辑 B 通道控制参数'));
    await tester.pumpAndSettle();
    expect(find.text('B 通道控制参数'), findsOneWidget);
    expect(desk.engine.state.selected, 'A');
    await tester.enterText(
      find.byKey(const ValueKey('linear-amount-B')),
      '-25',
    );
    await tester.enterText(find.byKey(const ValueKey('boost-amount-B')), '15');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(desk.engine.state.channels['A']!.linearAmount, 80);
    expect(desk.engine.state.channels['A']!.linearUnit, 'percent');
    expect(desk.engine.state.channels['A']!.boostAmount, 45);
    expect(desk.engine.state.channels['B']!.linearAmount, -25);
    expect(desk.engine.state.channels['B']!.linearUnit, 'absolute');
    expect(desk.engine.state.channels['B']!.boostAmount, 15);

    await tester.pumpWidget(const SizedBox());
    desk.dispose();
    monitor.dispose();
    unawaited(stream.close());
    await tester.pump();
  });

  test('active touch effects refresh when channel controls change', () async {
    final stream = StreamController<Map<String, dynamic>>();
    final monitor = InputMonitor(
      events: stream.stream,
      observeLifecycle: false,
    );
    final desk = ControlDesk(monitor, coyote: _FakeCoyote());
    await desk.initialize(storage: _MemoryStore(), assets: _LocalAssets());
    desk.engine.state.channels['A']!.base = 90;
    await desk.setChannelControls(
      'A',
      linearAmount: 60,
      linearUnit: 'absolute',
      boostAmount: 40,
    );
    desk.engine.state
      ..touchMode = true
      ..touchSurfaceVisible = true
      ..touchChannel = 'A'
      ..beginScreenTouch(0.5, 0.5);
    desk.engine.input(GamepadState.neutral, live: true, deviceId: 'pad');
    desk.engine.input(
      GamepadState({Control.leftTrigger: 0.5, Control.leftShoulder: 1}),
      live: true,
      deviceId: 'pad',
    );
    expect(desk.engine.state.touchReadout('A')!.intensity, 160);

    await desk.setChannelControls(
      'A',
      linearAmount: 50,
      linearUnit: 'percent',
      boostAmount: 20,
    );
    expect(desk.engine.state.touchReadout('A')!.intensity, 132.5);

    desk.dispose();
    monitor.dispose();
    unawaited(stream.close());
  });

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

  testWidgets('gamepad operations reveal offscreen target cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    Map<String, dynamic> snapshot(Map<String, double> values) => {
      'version': 1,
      'type': 'snapshot',
      'devices': [
        {
          'id': 'pad',
          'name': 'Pad',
          'family': 'xbox',
          'transport': 'usb',
          'capabilities': ['down', 'rightShoulder'],
          'values': values,
        },
      ],
    };

    final dashboard = find.byType(ListView).first;
    final scrollable = find.descendant(
      of: dashboard,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final viewport = tester.getRect(dashboard);
    stream.add(snapshot({}));
    await tester.pump();

    stream.add(snapshot({'down': 1}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(desk.engine.state.focusTarget?.area, ControlFocusArea.waveform);
    expect(desk.engine.state.focusTarget?.waveformIndex, 2);
    expect(position.pixels, greaterThan(0));
    final waveformTitle = find.text(waveforms[2].name).first;
    expect(
      tester.getRect(waveformTitle).top,
      greaterThanOrEqualTo(viewport.top),
    );
    expect(
      tester.getRect(waveformTitle).bottom,
      lessThanOrEqualTo(viewport.bottom),
    );

    stream.add(snapshot({}));
    await tester.pump();
    stream.add(snapshot({'rightShoulder': 1}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(desk.engine.state.focusTarget?.area, ControlFocusArea.channel);
    expect(desk.engine.state.focusTarget?.channel, 'B');
    final channelCard = find
        .ancestor(of: find.text('B 通道').first, matching: find.byType(Material))
        .first;
    final channelRect = tester.getRect(channelCard);
    expect(channelRect.top, greaterThanOrEqualTo(viewport.top));
    expect(channelRect.bottom, lessThanOrEqualTo(viewport.bottom));

    await desk.setBinding(
      Binding(
        id: 'down',
        input: 'down',
        action: 'builtin.waveform',
        config: {
          'target': 'B',
          'mode': 'fixed',
          'waveform': waveforms[5].id,
          'list': [waveforms.first.id],
        },
      ),
    );
    stream.add(snapshot({}));
    await tester.pump();
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    stream.add(snapshot({'down': 1}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(desk.engine.state.focusTarget?.area, ControlFocusArea.waveform);
    expect(desk.engine.state.focusTarget?.channel, 'B');
    expect(desk.engine.state.focusTarget?.waveformIndex, 5);
    final updatedChannelRect = tester.getRect(channelCard);
    expect(updatedChannelRect.top, greaterThanOrEqualTo(viewport.top));
    expect(updatedChannelRect.bottom, lessThanOrEqualTo(viewport.bottom));

    final follow = find.textContaining('自动滚动');
    expect(find.textContaining('自动滚动'), findsOneWidget);
    await tester.tap(follow);
    await tester.pump();
    expect(desk.autoScrollToAction, isFalse);
    expect(find.text('自动滚动：关'), findsOneWidget);
    stream.add(snapshot({}));
    await tester.pump();
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final manualOffset = position.pixels;
    stream.add(snapshot({'down': 1}));
    await tester.pump();
    expect(position.pixels, manualOffset);

    await tester.pumpWidget(const SizedBox());
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

    final surface = find.byKey(const ValueKey('touch-surface'));
    final trail = find.descendant(
      of: surface,
      matching: find.byType(CustomPaint),
    );
    int particleCount() =>
        (tester.widget<CustomPaint>(trail).painter as dynamic).particleCount
            as int;
    expect(particleCount(), 0);
    stream.add(snapshot({'rightX': 1}));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(particleCount(), greaterThan(0));

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
