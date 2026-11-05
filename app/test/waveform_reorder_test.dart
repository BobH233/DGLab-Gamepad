import 'dart:io';

import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/control/control_store.dart';
import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/ui/control/control_home.dart';
import 'package:dglab_gamepad/ui/control/waveform_view.dart';
import 'package:dglab_gamepad/ui/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (size, reduceMotion) in [
    (const Size(390, 844), false),
    (const Size(932, 430), false),
    (const Size(390, 844), true),
  ]) {
    testWidgets('long press reorders $size with reduced motion $reduceMotion', (
      tester,
    ) async {
      final (desk, monitor, store) = await _mount(
        tester,
        size: size,
        reduceMotion: reduceMotion,
      );
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      TestGesture? gesture;
      try {
        final before = waveforms.map((waveform) => waveform.id).toList();
        desk.chooseWaveform(8);
        desk.engine.state.channels['B']!.waveform = before[10];
        await tester.pump();
        final source = find.byKey(ValueKey(before.first));
        final targetIndex = size.width > 600 ? 5 : 3;
        final target = find.byKey(ValueKey(before[targetIndex]));
        await tester.ensureVisible(source);
        await tester.pumpAndSettle();
        desk.engine.state.channels['A']!.enabled = true;
        desk.engine.publish();
        final output = desk.output.latest!.channels;
        final targetCenter = tester.getCenter(target);
        final sourceCenter = tester.getCenter(source);
        final neighborBefore = tester.getTopLeft(target);
        final preview = find.descendant(
          of: source,
          matching: find.byType(WaveformView),
        );
        final previewSize = tester.getSize(preview);

        gesture = await tester.startGesture(sourceCenter);
        await tester.pump(const Duration(milliseconds: 400));
        expect(haptics, isEmpty);
        await tester.pump(const Duration(milliseconds: 60));
        expect(haptics, hasLength(1));
        expect(haptics.single.arguments, 'HapticFeedbackType.selectionClick');
        await tester.pump(const Duration(milliseconds: 180));
        expect(tester.getSize(preview.last), previewSize);

        await gesture.moveTo(targetCenter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getTopLeft(target), isNot(neighborBefore));
        expect(waveforms.map((waveform) => waveform.id), before);
        expect(desk.engine.state.channels['A']!.waveform, before[8]);
        await gesture.up();
        gesture = null;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        final expected = [...before]
          ..removeAt(0)
          ..insert(targetIndex, before.first);
        expect(waveforms.map((waveform) => waveform.id), expected);
        expect(store.value!['waveformOrder'], expected);
        expect(desk.output.latest!.channels, output);
        expect(haptics, hasLength(1));
        expect(tester.takeException(), isNull);

        await tester.tap(source);
        await tester.pump();
        expect(desk.engine.state.channels['A']!.waveform, before.first);

        final firstSlot = tester.getCenter(find.byKey(ValueKey(before[1])));
        gesture = await tester.startGesture(tester.getCenter(source));
        await tester.pump(const Duration(milliseconds: 500));
        await gesture.moveTo(firstSlot);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        gesture = null;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(waveforms.map((waveform) => waveform.id), before);
        expect(store.value!['waveformOrder'], before);
        expect(tester.takeException(), isNull);
      } finally {
        await gesture?.cancel();
        await tester.pumpWidget(const SizedBox());
        desk.dispose();
        monitor.dispose();
        setCustomWaveformCatalog(const []);
        await tester.pump();
      }
    });
  }

  testWidgets('edge scrolling allows dragging the first waveform to the end', (
    tester,
  ) async {
    final (desk, monitor, _) = await _mount(tester);
    TestGesture? gesture;
    try {
      final sourceId = waveforms.first.id;
      final source = find.byKey(ValueKey(sourceId));
      await tester.ensureVisible(source);
      await tester.pumpAndSettle();
      final dashboard = find.byType(ListView).first;
      final scrollable = find
          .descendant(of: dashboard, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final before = position.pixels;
      final viewport = tester.getRect(dashboard);
      gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 20));
      await tester.pump(const Duration(milliseconds: 800));
      expect(position.pixels, greaterThan(before));
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.up();
      gesture = null;
      await tester.pumpAndSettle();
      expect(waveforms.last.id, sourceId);
      expect(tester.takeException(), isNull);
    } finally {
      await gesture?.cancel();
      await tester.pumpWidget(const SizedBox());
      desk.dispose();
      monitor.dispose();
      setCustomWaveformCatalog(const []);
      await tester.pump();
    }
  });

  testWidgets('screen reader actions reorder a waveform without selecting it', (
    tester,
  ) async {
    final (desk, monitor, store) = await _mount(tester);
    try {
      final before = waveforms.map((waveform) => waveform.id).toList();
      final card = find.byKey(ValueKey(before[1]));
      final semantics = tester.widget<Semantics>(
        find.descendant(of: card, matching: find.byType(Semantics)).first,
      );
      semantics.properties.customSemanticsActions![const CustomSemanticsAction(
        label: '向前移动',
      )]!();
      await tester.pumpAndSettle();
      expect(waveforms.take(2).map((waveform) => waveform.id), [
        before[1],
        before[0],
      ]);
      expect(store.value!['waveformOrder'].first, before[1]);
      expect(desk.engine.state.channels['A']!.waveform, before[0]);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      desk.dispose();
      monitor.dispose();
      setCustomWaveformCatalog(const []);
      await tester.pump();
    }
  });
}

Future<(ControlDesk, InputMonitor, _MemoryStore)> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final monitor = InputMonitor(
    events: const Stream.empty(),
    observeLifecycle: false,
  );
  final desk = ControlDesk(monitor);
  final store = _MemoryStore();
  await desk.initialize(storage: store, assets: _LocalAssets());
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
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(1.5),
        ),
        child: child!,
      ),
      home: ControlHome(desk: desk),
    ),
  );
  await tester.pumpAndSettle();
  return (desk, monitor, store);
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
