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

  for (final size in _screenSizes) {
    testWidgets('stable displacement, live updates and rapid reversals $size', (
      tester,
    ) async {
      final (desk, monitor, store) = await _mount(tester, size: size);
      TestGesture? gesture;
      try {
        final ids = waveforms.map((w) => w.id).toList();
        final source = find.byKey(ValueKey(ids.first));
        await _centerFirstRows(tester, source);
        final grid = tester.widget<GridView>(find.byType(GridView));
        final columns =
            (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount;
        final slots = [
          for (final id in ids) tester.getTopLeft(find.byKey(ValueKey(id))),
        ];
        final cardSize = tester.getSize(source);
        final sourceCenter = tester.getCenter(source);
        final targets = [
          columns - 1,
          2 * columns - 1,
          columns,
          0,
          2 * columns - 1,
          1,
        ];
        gesture = await tester.startGesture(sourceCenter);
        await tester.pump(const Duration(milliseconds: 500));
        for (final target in targets) {
          await gesture.moveTo(slots[target] + cardSize.center(Offset.zero));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          final order = [...ids]
            ..removeAt(0)
            ..insert(target, ids.first);
          for (var refresh = 0; refresh < 3; refresh++) {
            desk.setBase(
              'B',
              desk.engine.state.channels['B']!.base + 1,
              persist: false,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            for (final id in ids.skip(1)) {
              expect(
                tester.getTopLeft(find.byKey(ValueKey(id))),
                slots[order.indexOf(id)],
                reason: '$id at target $target after refresh $refresh',
              );
            }
          }
        }
        for (final target in targets.reversed) {
          final previous = {
            for (final id in ids.skip(1))
              id: tester.getTopLeft(find.byKey(ValueKey(id))),
          };
          await gesture.moveTo(slots[target] + cardSize.center(Offset.zero));
          desk.setBase(
            'B',
            desk.engine.state.channels['B']!.base + 1,
            persist: false,
          );
          await tester.pump();
          for (final id in ids.skip(1)) {
            expect(
              (tester.getTopLeft(find.byKey(ValueKey(id))) - previous[id]!)
                  .distance,
              lessThan(0.01),
              reason: '$id must retarget from its visible position',
            );
          }
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            for (final id in ids.skip(1)) {
              final rect = tester.getRect(find.byKey(ValueKey(id)));
              expect(rect.left, greaterThanOrEqualTo(slots.first.dx - 0.01));
              expect(
                rect.right,
                lessThanOrEqualTo(
                  slots[columns - 1].dx + cardSize.width + 0.01,
                ),
              );
            }
          }
        }
        final beforeRelease = {
          for (final id in ids.skip(1))
            id: tester.getTopLeft(find.byKey(ValueKey(id))),
        };
        await gesture.up();
        gesture = null;
        await tester.pump();
        for (final id in ids.skip(1)) {
          expect(
            (tester.getTopLeft(find.byKey(ValueKey(id))) - beforeRelease[id]!)
                .distance,
            lessThan(0.01),
            reason: '$id must not jump on release',
          );
        }
        for (var frame = 0; frame < 16; frame++) {
          desk.setBase('B', frame.toDouble(), persist: false);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        final expected = [...ids]
          ..removeAt(0)
          ..insert(targets.first, ids.first);
        expect(waveforms.map((w) => w.id), expected);
        expect(store.value!['waveformOrder'], expected);
        for (var index = 0; index < ids.length; index++) {
          expect(
            tester.getTopLeft(find.byKey(ValueKey(expected[index]))),
            slots[index],
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await gesture?.up();
        await tester.pumpWidget(const SizedBox());
        desk.dispose();
        monitor.dispose();
        setCustomWaveformCatalog(const []);
        await tester.pump();
      }
    });

    testWidgets('imported waveforms drag among built-ins and restore $size', (
      tester,
    ) async {
      final (desk, monitor, store) = await _mount(tester, size: size);
      ControlDesk? restored;
      TestGesture? gesture;
      try {
        final first = await desk.importPulseWaveform(
          'Dungeonlab+pulse:0,1,16=0,0,0,1,1/0-1,100-1',
          name: '导入甲',
        );
        await tester.pumpAndSettle();
        final second = await desk.importPulseWaveform(
          'Dungeonlab+pulse:0,1,16=0,0,0,1,1/0-1,80-1',
          name: '导入乙',
        );
        await tester.pumpAndSettle();
        final expected = waveforms.map((w) => w.id).toList();
        desk.engine.state.channels['B']!.waveform = first.id;
        for (final id in [second.id, first.id]) {
          final source = find.byKey(ValueKey(id));
          await _centerFirstRows(tester, find.byKey(ValueKey(expected.first)));
          final columns =
              (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                      as SliverGridDelegateWithFixedCrossAxisCount)
                  .crossAxisCount;
          final targetIndex = columns * 2 - 1;
          final targetCenter = tester.getCenter(
            find.byKey(ValueKey(expected[targetIndex])),
          );
          gesture = await tester.startGesture(tester.getCenter(source));
          await tester.pump(const Duration(milliseconds: 500));
          await gesture.moveTo(targetCenter);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          desk.setBase('B', 20, persist: false);
          await tester.pump();
          await gesture.up();
          gesture = null;
          await tester.pumpAndSettle();
          expected.remove(id);
          expected.insert(targetIndex, id);
          expect(waveforms.map((w) => w.id), expected);
          expect(store.value!['waveformOrder'], expected);
          expect(desk.engine.state.channels['A']!.waveform, second.id);
          expect(desk.engine.state.channels['B']!.waveform, first.id);
        }
        await tester.pumpWidget(const SizedBox());
        restored = ControlDesk(monitor);
        await restored.initialize(storage: store, assets: _LocalAssets());
        expect(waveforms.map((w) => w.id), expected);
        expect(waveforms.where((w) => w.isCustom).map((w) => w.id).toSet(), {
          first.id,
          second.id,
        });
        expect(tester.takeException(), isNull);
      } finally {
        await gesture?.up();
        await tester.pumpWidget(const SizedBox());
        desk.dispose();
        restored?.dispose();
        monitor.dispose();
        setCustomWaveformCatalog(const []);
        await tester.pump();
      }
    });

    testWidgets(
      'edge scrolling with live updates keeps cards in the grid $size',
      (tester) async {
        final (desk, monitor, _) = await _mount(tester, size: size);
        TestGesture? gesture;
        try {
          if (size.shortestSide > 600) {
            for (var i = 0; i < 32; i++) {
              await desk.importPulseWaveform(
                'Dungeonlab+pulse:0,1,16=0,0,0,1,1/0-1,${i + 1}-1',
                name: '滚动测试 $i',
              );
            }
            expect(desk.customWaveforms, hasLength(32));
            await tester.pumpAndSettle();
          }
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
          final gridRect = tester.getRect(find.byType(GridView));
          final lastSlot = tester.getCenter(
            find.byKey(ValueKey(waveforms.last.id)),
          );
          gesture = await tester.startGesture(tester.getCenter(source));
          await tester.pump(const Duration(milliseconds: 500));
          await gesture.moveTo(
            Offset(viewport.center.dx, viewport.bottom - 20),
          );
          for (var frame = 0; frame < 32; frame++) {
            desk.setBase('B', frame.toDouble(), persist: false);
            await tester.pump(const Duration(milliseconds: 50));
            for (final waveform in waveforms.skip(1)) {
              final rect = tester.getRect(find.byKey(ValueKey(waveform.id)));
              expect(rect.left, greaterThanOrEqualTo(gridRect.left - 0.01));
              expect(rect.right, lessThanOrEqualTo(gridRect.right + 0.01));
            }
          }
          expect(position.pixels, greaterThan(before));
          final lastCenter = lastSlot - Offset(0, position.pixels - before);
          await gesture.moveTo(
            Offset(
              lastCenter.dx,
              lastCenter.dy.clamp(viewport.top + 1, viewport.bottom - 1),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          await gesture.up();
          gesture = null;
          await tester.pumpAndSettle();
          expect(waveforms.last.id, sourceId);
          final grid = tester.widget<GridView>(find.byType(GridView));
          final columns =
              (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                  .crossAxisCount;
          final origin = tester.getTopLeft(find.byType(GridView));
          final width = (gridRect.width - (columns - 1) * 12) / columns;
          for (var i = 0; i < waveforms.length; i++) {
            expect(
              tester.getTopLeft(find.byKey(ValueKey(waveforms[i].id))),
              origin + Offset(i % columns * (width + 12), i ~/ columns * 127),
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await gesture?.cancel();
          await tester.pumpWidget(const SizedBox());
          desk.dispose();
          monitor.dispose();
          setCustomWaveformCatalog(const []);
          await tester.pump();
        }
      },
    );
  }

  for (final portrait in [const Size(390, 844), const Size(820, 1180)]) {
    testWidgets('rotation and cancelled drag allow another reorder $portrait', (
      tester,
    ) async {
      final (desk, monitor, _) = await _mount(tester, size: portrait);
      TestGesture? gesture;
      try {
        final ids = waveforms.map((w) => w.id).toList();
        for (final size in [
          portrait,
          Size(portrait.height, portrait.width),
          portrait,
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final source = find.byKey(ValueKey(ids.first));
          await _centerFirstRows(tester, source);
          gesture = await tester.startGesture(tester.getCenter(source));
          await tester.pump(const Duration(milliseconds: 500));
          await gesture.cancel();
          gesture = null;
          await tester.pumpAndSettle();
          desk.setBase(
            'B',
            desk.engine.state.channels['B']!.base + 1,
            persist: false,
          );
          await tester.pump();
          final order = waveforms.map((w) => w.id).toList();
          final target = order.indexOf(ids.first) == 0 ? 1 : 0;
          final targetCenter = tester.getCenter(
            find.byKey(ValueKey(order[target])),
          );
          gesture = await tester.startGesture(tester.getCenter(source));
          await tester.pump(const Duration(milliseconds: 500));
          await gesture.moveTo(targetCenter);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          await gesture.up();
          gesture = null;
          await tester.pumpAndSettle();
          order.remove(ids.first);
          order.insert(target, ids.first);
          expect(waveforms.map((w) => w.id), order);
          expect(tester.takeException(), isNull);
        }
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

const _screenSizes = [
  Size(390, 844),
  Size(844, 390),
  Size(820, 1180),
  Size(1180, 820),
  Size(1024, 1366),
  Size(1366, 1024),
];

Future<void> _centerFirstRows(WidgetTester tester, Finder source) async {
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  final dashboard = find.byType(ListView).first;
  final viewport = tester.getRect(dashboard);
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: dashboard, matching: find.byType(Scrollable)).first,
      )
      .position;
  final top = viewport.top + (viewport.height - 242) / 2;
  position.jumpTo(
    (position.pixels + tester.getTopLeft(source).dy - top).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ),
  );
  await tester.pumpAndSettle();
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
