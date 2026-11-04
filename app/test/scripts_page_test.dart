import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dglab_gamepad/control/control_desk.dart';
import 'package:dglab_gamepad/control/control_store.dart';
import 'package:dglab_gamepad/input/input_monitor.dart';
import 'package:dglab_gamepad/ui/control/scripts_page.dart';
import 'package:dglab_gamepad/ui/palette.dart';

void main() {
  testWidgets('imported scripts can be renamed from the scripts page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final monitor = InputMonitor(
      events: const Stream.empty(),
      observeLifecycle: false,
    );
    final store = _MemoryStore();
    final desk = ControlDesk(monitor);
    await desk.initialize(storage: store, assets: _Assets());
    final action = desk.validateScript(
      File('assets/scripts/example.js').readAsStringSync(),
    );
    await desk.install(action);
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
        home: Scaffold(body: ScriptsPage(desk: desk)),
      ),
    );

    expect(find.byTooltip('重命名脚本'), findsOneWidget);
    await tester.tap(find.byTooltip('重命名脚本'));
    await tester.pumpAndSettle();
    expect(find.text('重命名脚本'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('script-rename-field')),
      '我的点火操作',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(desk.actions[action.id]!.name, '我的点火操作');
    expect(find.text('我的点火操作'), findsOneWidget);
    expect(store.value!['scriptNames'], {action.id: '我的点火操作'});

    await tester.pumpWidget(const SizedBox());
    desk.dispose();
    monitor.dispose();
  });
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

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}
