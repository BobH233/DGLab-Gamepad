import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final desk = ControlDesk(monitor);
      final storage = _MemoryStore();
      await desk.initialize(storage: storage, assets: _LocalAssets());
      expect(desk.ready, isTrue, reason: desk.error);
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
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('A 强度加一'));
      await desk.save();
      await tester.pump();
      expect(desk.engine.state.channels['A']!.base, 1);
      await tester.tap(find.byTooltip('启动 A 通道'));
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isTrue);
      await tester.tap(find.text('全部停止'));
      await tester.pump();
      expect(desk.engine.state.enabled('A'), isFalse);
      expect(desk.engine.state.channels['A']!.base, 1);
      await tester.ensureVisible(find.text('B 通道').first);
      await tester.tap(find.text('B 通道').first);
      await tester.pump();
      expect(desk.engine.state.selected, 'B');
      final scroll = find.byType(SingleChildScrollView).first;
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
