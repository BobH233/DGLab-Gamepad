import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gamepad_core/gamepad_core.dart';
import '../../control/control_desk.dart';
import '../../control/models.dart';
import '../palette.dart';
import '../monitor_screen.dart';
import 'bindings_page.dart';
import 'coyote_sheet.dart';
import 'scripts_page.dart';
import 'touch_panel.dart';
import 'waveform_view.dart';

class ControlHome extends StatefulWidget {
  final ControlDesk desk;
  const ControlHome({super.key, required this.desk});
  @override
  State<ControlHome> createState() => _ControlHomeState();
}

class _ControlHomeState extends State<ControlHome> {
  int page = 0;
  int _lastTouchPanelRequest = 0;
  bool _openingTouch = false;
  ControlDesk get desk => widget.desk;

  @override
  void initState() {
    super.initState();
    _lastTouchPanelRequest = desk.engine.state.touchPanelRequest;
    desk.addListener(_handleDeskRequests);
  }

  @override
  void didUpdateWidget(ControlHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.desk != widget.desk) {
      oldWidget.desk.removeListener(_handleDeskRequests);
      widget.desk.addListener(_handleDeskRequests);
      _lastTouchPanelRequest = widget.desk.engine.state.touchPanelRequest;
    }
  }

  @override
  void dispose() {
    desk.removeListener(_handleDeskRequests);
    super.dispose();
  }

  void _handleDeskRequests() {
    final request = desk.engine.state.touchPanelRequest;
    if (request == _lastTouchPanelRequest) return;
    _lastTouchPanelRequest = request;
    final channel = desk.engine.state.touchPanelRequestChannel;
    if (channel == null || desk.editing) {
      return;
    }
    if (desk.touchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && desk.touchOpen) Navigator.of(context).pop();
      });
      return;
    }
    if (_openingTouch) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          desk.editing ||
          desk.touchOpen ||
          _openingTouch ||
          channel != desk.engine.state.touchPanelRequestChannel) {
        return;
      }
      _openingTouch = true;
      unawaited(
        showTouchPanelDialog(context, desk, channel).whenComplete(() {
          _openingTouch = false;
        }),
      );
    });
  }

  void navigate(int value) {
    if (value == page) return;
    if (value == 0) {
      desk.endEdit();
    } else {
      desk.beginEdit();
    }
    setState(() => page = value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: desk,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          children: [
                            const Text(
                              'DG-LAB',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Palette.yellow,
                                letterSpacing: -0.6,
                              ),
                            ),
                            if (MediaQuery.sizeOf(context).width >= 600) ...[
                              const SizedBox(width: 14),
                              Text(
                                ['控制台', '按键绑定', '操作脚本'][page],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Palette.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '手柄监测',
                    icon: const Icon(
                      Icons.sports_esports_outlined,
                      color: Palette.yellow,
                    ),
                    onPressed: () async {
                      desk.beginEdit();
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MonitorScreen(monitor: desk.monitor),
                        ),
                      );
                      if (page == 0) desk.endEdit();
                    },
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: desk.stopAll,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('全部停止'),
                  ),
                ],
              ),
            ),
            if (desk.error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  desk.error!,
                  style: const TextStyle(color: Palette.yellow),
                ),
              ),
            if (desk.persistenceError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  desk.persistenceError!,
                  style: const TextStyle(color: Palette.yellow, fontSize: 12),
                ),
              ),
            if (desk.loadWarnings.isNotEmpty)
              ExpansionTile(
                title: Text('${desk.loadWarnings.length} 项配置未载入'),
                children: [
                  for (final warning in desk.loadWarnings)
                    ListTile(title: Text(warning)),
                ],
              ),
            Expanded(
              child: !desk.ready
                  ? const Center(child: CircularProgressIndicator())
                  : switch (page) {
                      1 => BindingsPage(desk: desk),
                      2 => ScriptsPage(desk: desk),
                      _ => _dashboard(context),
                    },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: page,
        onDestinationSelected: navigate,
        backgroundColor: Palette.surface,
        indicatorColor: Palette.yellow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded, color: Palette.background),
            label: '控制台',
          ),
          NavigationDestination(
            icon: Icon(Icons.gamepad_outlined),
            selectedIcon: Icon(
              Icons.gamepad_outlined,
              color: Palette.background,
            ),
            label: '按键绑定',
          ),
          NavigationDestination(
            icon: Icon(Icons.code_rounded),
            selectedIcon: Icon(Icons.code_rounded, color: Palette.background),
            label: '操作脚本',
          ),
        ],
      ),
    ),
  );

  Widget _dashboard(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _connection(),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, c) {
                  final panels = [for (final id in channelIds) _channel(id)];
                  return c.maxWidth < 600
                      ? Column(
                          children: [
                            panels[0],
                            const SizedBox(height: 14),
                            panels[1],
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: panels[0]),
                            const SizedBox(width: 18),
                            Expanded(child: panels[1]),
                          ],
                        );
                },
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, c) => _waveforms(
                  c.maxWidth < 600
                      ? 2
                      : c.maxWidth < 900
                      ? 3
                      : 4,
                ),
              ),
              if (desk.engine.errors.isNotEmpty) ...[
                const SizedBox(height: 18),
                for (final entry in desk.engine.errors.entries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Palette.yellow),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Palette.yellow,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '绑定 ${entry.key} 已停用：${entry.value}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => navigate(1),
                          child: const Text('检查'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ],
  );

  Widget _connection() {
    final session = desk.monitor.session;
    final live = session.status == InputStatus.live;
    final status = switch (session.status) {
      InputStatus.live => '已连接',
      InputStatus.neutralRequired => '请松开所有按键',
      InputStatus.paused => '已暂停',
      InputStatus.disconnected => '已断开',
      InputStatus.stale => '输入中断',
      InputStatus.error => '输入不可用',
      _ => '未连接手柄',
    };
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              size: 17,
              color: live ? Palette.yellow : Palette.muted,
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: TextStyle(
                color: live ? Palette.yellow : Palette.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (session.device != null)
          Text(
            session.device!.name,
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        InkWell(
          onTap: () => showCoyoteSheet(context, desk.coyote),
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: desk.coyote.connected ? Palette.yellow : Palette.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bluetooth_rounded,
                  size: 14,
                  color: desk.coyote.connected ? Palette.yellow : Palette.muted,
                ),
                const SizedBox(width: 5),
                Text(
                  desk.coyote.connected
                      ? '${desk.coyote.deviceName ?? '郊狼 3'} · ${desk.coyote.batteryLevel ?? '--'}%'
                      : '连接郊狼',
                  style: TextStyle(
                    color: desk.coyote.connected
                        ? Palette.yellow
                        : Palette.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _channel(String id) {
    final state = desk.engine.state;
    final channel = state.channels[id]!;
    final selected = state.selected == id, enabled = state.enabled(id);
    final touchReadout = state.touchReadout(id);
    final touchTarget = state.touchMode && state.touchChannel == id;
    final live = touchTarget ? touchReadout != null : enabled;
    final offset = state.offset(id);
    final intensity = touchTarget
        ? touchReadout?.intensity.round() ?? 0
        : enabled
        ? state.effective(id).round()
        : 0;
    final status = touchTarget
        ? live
              ? '触控输出'
              : '等待触摸'
        : enabled
        ? '输出中'
        : '已停止';
    final wave = waveforms.firstWhere((w) => w.id == channel.waveform);
    return Material(
      color: Palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? Palette.yellow : Palette.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => desk.selectChannel(id),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            '$id 通道',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: selected ? Palette.yellow : Palette.text,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (selected)
                            const Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: Palette.yellow,
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '打开 $id 通道触控',
                    onPressed: () => showTouchPanelDialog(context, desk, id),
                    style: IconButton.styleFrom(
                      backgroundColor: Palette.raised,
                      foregroundColor: Palette.yellow,
                    ),
                    icon: const Icon(Icons.fingerprint_rounded, size: 21),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: enabled ? '停止 $id 通道' : '启动 $id 通道',
                    onPressed: () => desk.toggle(id),
                    style: IconButton.styleFrom(
                      backgroundColor: enabled
                          ? Palette.yellow
                          : Palette.raised,
                      foregroundColor: enabled
                          ? Palette.background
                          : Palette.yellow,
                    ),
                    icon: Icon(
                      enabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$intensity',
                    style: TextStyle(
                      fontSize: 64,
                      height: 1,
                      fontWeight: FontWeight.w300,
                      color: live ? Palette.yellow : Palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 6),
                    child: Text(
                      '/ 200',
                      style: TextStyle(color: Palette.muted, fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          color: live ? Palette.yellow : Palette.muted,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        wave.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Palette.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 54,
                width: double.infinity,
                child: WaveformView(waveform: wave, active: live),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '基础强度',
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${channel.base.round()}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '临时 ${offset >= 0 ? '+' : ''}${offset.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: offset.abs() > 0.1
                          ? Palette.yellow
                          : Palette.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _RepeatButton(
                    tooltip: '减少 $id 通道强度',
                    icon: Icons.remove_rounded,
                    onStep: () => desk.setBase(
                      id,
                      desk.engine.state.channels[id]!.base - 1,
                      persist: false,
                    ),
                    onEnd: () => unawaited(desk.save()),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(
                        context,
                      ).copyWith(inactiveTrackColor: Palette.line),
                      child: Slider(
                        value: channel.base,
                        min: 0,
                        max: 200,
                        allowedInteraction: SliderInteraction.slideThumb,
                        label: '${channel.base.round()}',
                        onChanged: (v) =>
                            desk.setBase(id, v.roundToDouble(), persist: false),
                        onChangeEnd: (_) => desk.save(),
                      ),
                    ),
                  ),
                  _RepeatButton(
                    tooltip: '增加 $id 通道强度',
                    icon: Icons.add_rounded,
                    onStep: () => desk.setBase(
                      id,
                      desk.engine.state.channels[id]!.base + 1,
                      persist: false,
                    ),
                    onEnd: () => unawaited(desk.save()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waveforms(int columns) {
    desk.engine.state.columns = columns;
    final selected = desk.engine.state.selected;
    final channel = desk.engine.state.channels[selected]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '波形预设',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            Text(
              '$selected 通道',
              style: const TextStyle(color: Palette.yellow, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < waveforms.length; i++)
                  SizedBox(
                    width: width,
                    height: 115,
                    child: _waveformCard(i, channel),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _waveformCard(int i, ChannelState channel) {
    final w = waveforms[i],
        current = w.id == channel.waveform,
        focused = i == channel.cursor;
    return InkWell(
      onTap: () => desk.chooseWaveform(i),
      onFocusChange: (focus) {
        if (focus) desk.focusWaveform(i);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: current
              ? Palette.yellow.withValues(alpha: 0.08)
              : Palette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused ? Palette.yellow : Palette.line,
            width: focused ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    w.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: current ? Palette.yellow : Palette.text,
                    ),
                  ),
                ),
                if (current)
                  const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: Palette.yellow,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: WaveformView(waveform: w, active: current),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepeatButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onStep;
  final VoidCallback onEnd;

  const _RepeatButton({
    required this.tooltip,
    required this.icon,
    required this.onStep,
    required this.onEnd,
  });

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;

  void _tap() {
    widget.onStep();
    widget.onEnd();
  }

  void _startRepeat(LongPressStartDetails _) {
    _timer?.cancel();
    widget.onStep();
    _timer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => widget.onStep(),
    );
  }

  void _stopRepeat() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    widget.onEnd();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      label: widget.tooltip,
      onTap: _tap,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: _tap,
        onLongPressStart: _startRepeat,
        onLongPressCancel: _stopRepeat,
        onLongPressEnd: (_) => _stopRepeat(),
        child: Material(
          color: Palette.yellow,
          shape: const CircleBorder(),
          child: SizedBox.square(
            dimension: 38,
            child: Icon(widget.icon, size: 20, color: Palette.background),
          ),
        ),
      ),
    ),
  );
}
