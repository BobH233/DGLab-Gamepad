import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gamepad_core/gamepad_core.dart';
import '../input/input_monitor.dart';
import 'gamepad_diagram.dart';
import 'palette.dart';

const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFeatures: [FontFeature.tabularFigures()],
);

class MonitorScreen extends StatefulWidget {
  final InputMonitor monitor;
  const MonitorScreen({super.key, required this.monitor});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  InputMonitor get monitor => widget.monitor;
  GamepadAppearance appearance = GamepadAppearance.direwolf;

  String statusText(InputStatus status) => switch (status) {
    InputStatus.waiting => '等待手柄连接',
    InputStatus.live => '实时接收',
    InputStatus.neutralRequired => '请释放按键与摇杆',
    InputStatus.paused => '已暂停',
    InputStatus.disconnected => '手柄已断开',
    InputStatus.stale => '输入连接中断',
    InputStatus.error => '输入不可用',
  };

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: monitor.exportJson()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制输入记录')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: monitor,
        builder: (context, _) {
          final session = monitor.session;
          final device = session.device;
          final state = session.state;
          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 600 ? 20 : 40,
              vertical: 28,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '返回控制台',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Palette.yellow,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'DG-LAB',
                                    style: TextStyle(
                                      fontFamily: 'Arial',
                                      color: Palette.yellow,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    '手柄监测',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Palette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '复制输入记录',
                            onPressed: () => _copy(context),
                            icon: const Icon(
                              Icons.ios_share_rounded,
                              size: 20,
                              color: Palette.yellow,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 720;
                          final controller = _controllerPanel(
                            context,
                            device,
                            state,
                          );
                          final data = _dataPanel(context);
                          return compact
                              ? Column(
                                  children: [
                                    controller,
                                    const SizedBox(height: 18),
                                    data,
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 8, child: controller),
                                    const SizedBox(width: 22),
                                    Expanded(flex: 4, child: data),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 22),
                      _diagnostics(context),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _controllerPanel(
    BuildContext context,
    GamepadDevice? device,
    GamepadState state,
  ) {
    final session = monitor.session;
    final live = session.status == InputStatus.live;
    return Container(
      decoration: BoxDecoration(
        color: Palette.surface.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: live ? Palette.yellow : Palette.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText(session.status),
                    style: TextStyle(
                      color: live ? Palette.yellow : Palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: monitor.paused ? '继续监测' : '暂停监测',
                  onPressed: monitor.togglePause,
                  icon: Icon(
                    monitor.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 20,
                  ),
                  color: Palette.yellow,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: session.devices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 8),
                    child: Text(
                      '未连接手柄',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: session.selectedId,
                      hint: const Text('选择手柄'),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        color: Palette.muted,
                        size: 20,
                      ),
                      dropdownColor: Palette.raised,
                      style: const TextStyle(
                        fontSize: 19,
                        color: Palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        for (final d in session.devices.values)
                          DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              d.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) monitor.select(id);
                      },
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              device == null
                  ? '在系统蓝牙设置中配对手柄'
                  : device.metadata['category'] as String? ?? '标准游戏手柄',
              style: const TextStyle(fontSize: 11, color: Palette.muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Row(
              children: [
                const Text(
                  '外观',
                  style: TextStyle(color: Palette.muted, fontSize: 11),
                ),
                const SizedBox(width: 10),
                DropdownButtonHideUnderline(
                  child: DropdownButton<GamepadAppearance>(
                    value: appearance,
                    isDense: true,
                    style: const TextStyle(color: Palette.muted, fontSize: 11),
                    icon: const Icon(Icons.expand_more_rounded, size: 16),
                    items: const [
                      DropdownMenuItem(
                        value: GamepadAppearance.direwolf,
                        child: Text('冰原狼 2'),
                      ),
                      DropdownMenuItem(
                        value: GamepadAppearance.system,
                        child: Text('通用布局'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => appearance = value);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
            child: RepaintBoundary(
              child: GamepadDiagram(
                state: state,
                device: device,
                appearance: appearance,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in Control.values.where((c) => !isAxis(c)))
                  if (device?.capabilities.contains(c) ?? false)
                    _key(device!.label(c), state[c] > 0.1),
              ],
            ),
          ),
          if (monitor.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: Text(
                monitor.error!,
                style: const TextStyle(color: Palette.yellow, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(String text, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: active ? Palette.yellow : Palette.surface,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: active ? Palette.yellow : Palette.line),
    ),
    child: Text(
      text,
      style: _mono.copyWith(
        fontSize: 10,
        color: active ? Palette.background : Palette.muted,
      ),
    ),
  );

  Widget _dataPanel(BuildContext context) {
    final s = monitor.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 16),
          child: Text(
            '实时输入',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        Row(
          children: [
            Expanded(child: _stickReadout('左摇杆', Control.leftX, Control.leftY)),
            const SizedBox(width: 12),
            Expanded(
              child: _stickReadout('右摇杆', Control.rightX, Control.rightY),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _trigger('LT', Control.leftTrigger),
        const SizedBox(height: 14),
        _trigger('RT', Control.rightTrigger),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              '摇杆死区',
              style: TextStyle(fontSize: 12, color: Palette.muted),
            ),
            const Spacer(),
            Text(
              '${(s.normalizer.deadZone * 100).round()}%',
              style: _mono.copyWith(fontSize: 12, color: Palette.yellow),
            ),
          ],
        ),
        Slider(
          value: s.normalizer.deadZone,
          min: 0,
          max: 0.3,
          divisions: 30,
          label: '${(s.normalizer.deadZone * 100).round()}%',
          semanticFormatterCallback: (value) => '${(value * 100).round()}%',
          onChanged: monitor.setDeadZone,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _metric('输入变化 / 秒', '${monitor.updatesPerSecond}')),
            Expanded(child: _metric('已记录变化', '${monitor.changes}')),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: _mono.copyWith(fontSize: 22, color: Palette.text)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Palette.muted)),
    ],
  );

  Widget _stickReadout(String title, Control x, Control y) {
    final s = monitor.session;
    final supported = s.device?.capabilities.contains(x) ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: _StickPlot(
                s.state[x],
                s.state[y],
                s.raw[x],
                s.raw[y],
                s.normalizer.deadZone,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final c in [x, y])
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Text(
                    c == x ? 'X' : 'Y',
                    style: _mono.copyWith(fontSize: 10, color: Palette.muted),
                  ),
                  const Spacer(),
                  Text(
                    supported ? s.state[c].toStringAsFixed(3) : '—',
                    style: _mono.copyWith(fontSize: 12, color: Palette.yellow),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trigger(String title, Control control) {
    final s = monitor.session;
    final value = s.state[control];
    final supported = s.device?.capabilities.contains(control) ?? false;
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            s.device?.label(control) ?? title,
            style: _mono.copyWith(fontSize: 11, color: Palette.muted),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: Palette.raised,
              color: Palette.yellow,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            supported ? '${(value * 100).round()}%' : '—',
            textAlign: TextAlign.right,
            style: _mono.copyWith(fontSize: 11, color: Palette.yellow),
          ),
        ),
      ],
    );
  }

  Widget _diagnostics(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Palette.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        title: const Text('输入记录', style: TextStyle(fontSize: 14)),
        trailing: const Icon(
          Icons.expand_more_rounded,
          size: 20,
          color: Palette.muted,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '时间 / 按键 / 原始值',
                  style: TextStyle(fontSize: 11, color: Palette.muted),
                ),
              ),
              TextButton(
                onPressed: monitor.clearHistory,
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (monitor.history.isEmpty)
            const SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  '暂无输入记录',
                  style: TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final event in monitor.history) _historyRow(event),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _historyRow(Map<String, dynamic> event) {
    final values = event['values'] as Map<String, double>;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              '${((event['timeMs'] as int) / 1000).toStringAsFixed(2)} s',
              style: _mono.copyWith(fontSize: 11, color: Palette.muted),
            ),
          ),
          Expanded(
            child: Text(
              values.isEmpty
                  ? '设备切换'
                  : values.entries
                        .map((e) => '${e.key}  ${e.value.toStringAsFixed(3)}')
                        .join('    '),
              style: _mono.copyWith(fontSize: 11, color: Palette.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickPlot extends CustomPainter {
  final double x, y, rawX, rawY, deadZone;
  _StickPlot(this.x, this.y, this.rawX, this.rawY, this.deadZone);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final p = Paint()
      ..isAntiAlias = true
      ..color = Palette.raised;
    canvas.drawCircle(center, radius, p);
    canvas.drawCircle(center, radius * deadZone, p..color = Palette.line);
    p
      ..color = Palette.line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, p);
    canvas.drawLine(center - Offset(radius, 0), center + Offset(radius, 0), p);
    canvas.drawLine(center - Offset(0, radius), center + Offset(0, radius), p);
    canvas.drawCircle(
      center + Offset(rawX, rawY) * radius,
      4,
      p..color = Palette.muted,
    );
    final target = center + Offset(x, y) * radius;
    canvas.drawLine(
      center,
      target,
      p..color = Palette.yellow.withValues(alpha: 0.5),
    );
    p
      ..style = PaintingStyle.fill
      ..color = Palette.yellow;
    canvas.drawCircle(target, 4, p);
  }

  @override
  bool shouldRepaint(covariant _StickPlot old) =>
      old.x != x ||
      old.y != y ||
      old.rawX != rawX ||
      old.rawY != rawY ||
      old.deadZone != deadZone;
}
