import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:gamepad_core/gamepad_core.dart';
import '../../control/control_desk.dart';
import '../../control/control_state.dart';
import '../../control/models.dart';
import '../../control/pulse_import.dart';
import '../../platform/display_orientation.dart';
import '../palette.dart';
import '../monitor_screen.dart';
import 'bindings_page.dart';
import 'channel_controls_dialog.dart';
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

class _ControlHomeState extends State<ControlHome> with WidgetsBindingObserver {
  int page = 0;
  int _lastFocusRequest = 0;
  int _lastTouchPanelRequest = 0;
  bool _focusScrollScheduled = false;
  bool _openingTouch = false;
  bool _railSideRefreshScheduled = false;
  NavigationRailSide? _platformRailSide;
  final Map<String, GlobalKey> _channelKeys = {
    for (final id in channelIds) id: GlobalKey(),
  };
  final Map<String, GlobalKey> _waveformKeys = {};
  ControlDesk get desk => widget.desk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastFocusRequest = desk.engine.state.focusRequest;
    _lastTouchPanelRequest = desk.engine.state.touchPanelRequest;
    desk.addListener(_handleDeskChanges);
    _scheduleRailSideRefresh();
  }

  @override
  void didUpdateWidget(ControlHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.desk != widget.desk) {
      oldWidget.desk.removeListener(_handleDeskChanges);
      widget.desk.addListener(_handleDeskChanges);
      _lastFocusRequest = widget.desk.engine.state.focusRequest;
      _lastTouchPanelRequest = widget.desk.engine.state.touchPanelRequest;
    }
  }

  @override
  void dispose() {
    desk.removeListener(_handleDeskChanges);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _scheduleRailSideRefresh();

  void _scheduleRailSideRefresh() {
    if (_railSideRefreshScheduled) return;
    _railSideRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _railSideRefreshScheduled = false;
      final side = await DisplayOrientation.navigationSide();
      if (!mounted || side == null || side == _platformRailSide) return;
      setState(() => _platformRailSide = side);
    });
  }

  void _handleDeskChanges() {
    _handleTouchRequest();
    _handleFocusRequest();
  }

  void _handleTouchRequest() {
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

  void _handleFocusRequest() {
    final request = desk.engine.state.focusRequest;
    if (request == _lastFocusRequest) return;
    _lastFocusRequest = request;
    if (!desk.autoScrollToAction || page != 0 || _focusScrollScheduled) {
      return;
    }
    _focusScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScrollScheduled = false;
      if (!mounted || !desk.autoScrollToAction || page != 0) return;
      final target = desk.engine.state.focusTarget;
      if (target != null) unawaited(_revealFocus(target));
    });
  }

  Future<void> _revealFocus(ControlFocusTarget target) async {
    final area =
        target.area == ControlFocusArea.waveform &&
            target.channel != desk.engine.state.selected
        ? ControlFocusArea.channel
        : target.area;
    final key = switch (area) {
      ControlFocusArea.channel => _channelKeys[target.channel],
      ControlFocusArea.waveform =>
        target.waveformIndex >= 0 && target.waveformIndex < waveforms.length
            ? _waveformKey(waveforms[target.waveformIndex].id)
            : null,
    };
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    final targetBox = targetContext.findRenderObject();
    final scrollable = Scrollable.of(targetContext);
    final viewportBox = scrollable.context.findRenderObject();
    if (targetBox is! RenderBox || viewportBox is! RenderBox) return;
    final top = targetBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final bottom = targetBox
        .localToGlobal(
          Offset(targetBox.size.width, targetBox.size.height),
          ancestor: viewportBox,
        )
        .dy;
    if (top >= 0 && bottom <= viewportBox.size.height) return;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: top < 0 ? 0.04 : 0.96,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
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

  GlobalKey _waveformKey(String id) =>
      _waveformKeys.putIfAbsent(id, GlobalKey.new);

  Future<void> _importPulse() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'DG-LAB pulse',
            extensions: ['pulse'],
            mimeTypes: ['text/plain'],
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > maxPulseFileBytes) {
        throw const FormatException('波形文件不能超过 512 KB');
      }
      final source = await file.readAsString();
      if (!mounted) return;
      final waveform = await showDialog<Waveform>(
        context: context,
        builder: (_) => _PulseImportDialog(
          desk: desk,
          source: source,
          initialName: pulseNameFromFile(file.name),
        ),
      );
      if (waveform != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导入 ${waveform.name}')));
      }
    } catch (e) {
      if (mounted) {
        final message = e is FormatException ? e.message : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compactLandscape = size.width > size.height && size.height < 600;
    final safePadding = MediaQuery.paddingOf(context);
    final fallbackRailOnRight = safePadding.left >= safePadding.right;
    final railOnRight = _platformRailSide == null
        ? fallbackRailOnRight
        : _platformRailSide == NavigationRailSide.right;
    final islandInset = railOnRight ? safePadding.left : safePadding.right;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: ListenableBuilder(
        listenable: desk,
        builder: (context, _) => Scaffold(
          body: SafeArea(
            key: const ValueKey('control-home-safe-area'),
            bottom: !compactLandscape,
            left: !compactLandscape,
            right: !compactLandscape,
            child: Stack(
              children: [
                Padding(
                  padding: compactLandscape
                      ? EdgeInsets.only(
                          left: railOnRight ? islandInset : 74,
                          right: railOnRight ? 74 : islandInset,
                        )
                      : EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: compactLandscape
                            ? const EdgeInsets.fromLTRB(16, 4, 10, 4)
                            : const EdgeInsets.fromLTRB(24, 20, 16, 14),
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
                                          fontFamily: 'Arial',
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: Palette.yellow,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      if (MediaQuery.sizeOf(context).width >=
                                          600) ...[
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
                              visualDensity: compactLandscape
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              constraints: compactLandscape
                                  ? const BoxConstraints.tightFor(
                                      width: 36,
                                      height: 36,
                                    )
                                  : null,
                              icon: const Icon(
                                Icons.sports_esports_outlined,
                                color: Palette.yellow,
                              ),
                              onPressed: () async {
                                desk.beginEdit();
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        MonitorScreen(monitor: desk.monitor),
                                  ),
                                );
                                if (page == 0) desk.endEdit();
                              },
                            ),
                            TextButton.icon(
                              onPressed: () => desk.setAutoScrollToAction(
                                !desk.autoScrollToAction,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: desk.autoScrollToAction
                                    ? Palette.yellow
                                    : Palette.muted,
                                minimumSize: Size(
                                  0,
                                  compactLandscape ? 34 : 40,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: compactLandscape ? 6 : 8,
                                ),
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              icon: Icon(
                                desk.autoScrollToAction
                                    ? Icons.center_focus_strong
                                    : Icons.center_focus_weak,
                                size: 18,
                              ),
                              label: Text(
                                '自动滚动：${desk.autoScrollToAction ? '开' : '关'}',
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (MediaQuery.sizeOf(context).width < 360)
                              IconButton(
                                tooltip: desk.anyChannelEnabled
                                    ? '全部停止'
                                    : '全部启动',
                                onPressed: desk.toggleAllChannels,
                                icon: Icon(
                                  desk.anyChannelEnabled
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: desk.toggleAllChannels,
                                style: compactLandscape
                                    ? OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 34),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      )
                                    : null,
                                icon: Icon(
                                  desk.anyChannelEnabled
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  desk.anyChannelEnabled ? '全部停止' : '全部启动',
                                ),
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
                            style: const TextStyle(
                              color: Palette.yellow,
                              fontSize: 12,
                            ),
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
                                _ => _dashboard(
                                  context,
                                  compactLandscape: compactLandscape,
                                ),
                              },
                      ),
                    ],
                  ),
                ),
                if (compactLandscape)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: railOnRight ? null : 0,
                    right: railOnRight ? 0 : null,
                    child: _sideNavigation(onRight: railOnRight),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: compactLandscape
              ? null
              : NavigationBarTheme(
                  data: NavigationBarThemeData(
                    labelTextStyle: WidgetStatePropertyAll(
                      const TextStyle(fontSize: 12),
                    ),
                  ),
                  child: NavigationBar(
                    height: 68,
                    selectedIndex: page,
                    onDestinationSelected: navigate,
                    backgroundColor: Palette.surface,
                    indicatorColor: Palette.yellow,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.tune_rounded),
                        selectedIcon: Icon(
                          Icons.tune_rounded,
                          color: Palette.background,
                        ),
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
                        selectedIcon: Icon(
                          Icons.code_rounded,
                          color: Palette.background,
                        ),
                        label: '操作脚本',
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _sideNavigation({required bool onRight}) => Align(
    alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        key: const ValueKey('compact-side-navigation'),
        color: Palette.surface,
        elevation: 4,
        shadowColor: Colors.black54,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Palette.line),
        ),
        child: SizedBox(
          width: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sideNavigationItem(
                  index: 0,
                  icon: Icons.tune_rounded,
                  label: '控制台',
                ),
                _sideNavigationItem(
                  index: 1,
                  icon: Icons.gamepad_outlined,
                  label: '按键绑定',
                ),
                _sideNavigationItem(
                  index: 2,
                  icon: Icons.code_rounded,
                  label: '操作脚本',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _sideNavigationItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = page == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => navigate(index),
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 40,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? Palette.yellow : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => navigate(index),
                  splashColor: selected
                      ? Palette.background.withValues(alpha: 0.14)
                      : Palette.yellow.withValues(alpha: 0.16),
                  highlightColor: Colors.transparent,
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? Palette.background : Palette.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: selected ? Palette.yellow : Palette.muted,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboard(BuildContext context, {required bool compactLandscape}) =>
      ListView(
        padding: compactLandscape
            ? const EdgeInsets.fromLTRB(16, 2, 16, 10)
            : const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _connection(compact: compactLandscape),
                  SizedBox(height: compactLandscape ? 8 : 22),
                  LayoutBuilder(
                    builder: (context, c) {
                      final panels = [
                        for (final id in channelIds)
                          _channel(id, compact: compactLandscape),
                      ];
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
                  SizedBox(height: compactLandscape ? 16 : 28),
                  LayoutBuilder(
                    builder: (context, c) => _waveforms(
                      c.maxWidth < 600
                          ? 2
                          : c.maxWidth < 900
                          ? 3
                          : 4,
                      compact: compactLandscape,
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

  Widget _connection({required bool compact}) {
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
      spacing: compact ? 12 : 16,
      runSpacing: compact ? 4 : 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              size: compact ? 15 : 17,
              color: live ? Palette.yellow : Palette.muted,
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              status,
              style: TextStyle(
                color: live ? Palette.yellow : Palette.muted,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
        if (session.device != null)
          Text(
            session.device!.name,
            style: TextStyle(color: Palette.muted, fontSize: compact ? 11 : 12),
          ),
        InkWell(
          onTap: () => showCoyoteSheet(context, desk.coyote),
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 9,
              vertical: compact ? 3 : 5,
            ),
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
                  size: compact ? 13 : 14,
                  color: desk.coyote.connected ? Palette.yellow : Palette.muted,
                ),
                SizedBox(width: compact ? 4 : 5),
                Text(
                  desk.coyote.connected
                      ? '${desk.coyote.deviceName ?? '郊狼 3'} · ${desk.coyote.batteryLevel ?? '--'}%'
                      : '连接郊狼',
                  style: TextStyle(
                    color: desk.coyote.connected
                        ? Palette.yellow
                        : Palette.muted,
                    fontSize: compact ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _channel(String id, {required bool compact}) {
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
      key: _channelKeys[id],
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
          padding: EdgeInsets.all(compact ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: compact ? 1 : 6),
                      child: Row(
                        children: [
                          Text(
                            '$id 通道',
                            style: TextStyle(
                              fontSize: compact ? 16 : 20,
                              fontWeight: FontWeight.w600,
                              color: selected ? Palette.yellow : Palette.text,
                            ),
                          ),
                          SizedBox(width: compact ? 7 : 10),
                          if (selected)
                            Icon(
                              Icons.check_circle_outline,
                              size: compact ? 14 : 16,
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
                      minimumSize: compact
                          ? const Size.square(34)
                          : const Size.square(48),
                      padding: EdgeInsets.zero,
                      tapTargetSize: compact
                          ? MaterialTapTargetSize.shrinkWrap
                          : MaterialTapTargetSize.padded,
                      visualDensity: compact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                    ),
                    icon: Icon(
                      Icons.fingerprint_rounded,
                      size: compact ? 18 : 21,
                    ),
                  ),
                  SizedBox(width: compact ? 2 : 4),
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
                      minimumSize: compact
                          ? const Size.square(34)
                          : const Size.square(48),
                      padding: EdgeInsets.zero,
                      tapTargetSize: compact
                          ? MaterialTapTargetSize.shrinkWrap
                          : MaterialTapTargetSize.padded,
                      visualDensity: compact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                    ),
                    icon: Icon(
                      enabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: compact ? 18 : null,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$intensity',
                    style: TextStyle(
                      fontSize: compact ? 42 : 64,
                      height: compact ? 0.9 : 1,
                      fontWeight: FontWeight.w300,
                      color: live ? Palette.yellow : Palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: compact ? 6 : 8,
                      bottom: compact ? 2 : 6,
                    ),
                    child: Text(
                      '/ 200',
                      style: TextStyle(
                        color: Palette.muted,
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: compact ? 10 : 12,
                          color: live ? Palette.yellow : Palette.muted,
                        ),
                      ),
                      SizedBox(height: compact ? 3 : 7),
                      Text(
                        wave.name,
                        style: TextStyle(
                          fontSize: compact ? 11 : 13,
                          color: Palette.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 16),
              SizedBox(
                height: compact ? 58 : 54,
                width: double.infinity,
                child: LiveWaveformView(
                  channel: id,
                  trace: desk.waveformTrace,
                  active: live,
                ),
              ),
              SizedBox(height: compact ? 8 : 16),
              Row(
                children: [
                  Text(
                    '基础强度',
                    style: TextStyle(
                      fontSize: compact ? 10 : 12,
                      color: Palette.muted,
                    ),
                  ),
                  SizedBox(width: compact ? 7 : 10),
                  Text(
                    '${channel.base.round()}',
                    style: TextStyle(
                      fontSize: compact ? 12 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: '编辑 $id 通道控制参数',
                    child: InkWell(
                      onTap: () => showChannelControlsDialog(context, desk, id),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 7 : 9,
                          vertical: compact ? 3 : 5,
                        ),
                        decoration: BoxDecoration(
                          color: Palette.raised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: offset.abs() > 0.1
                                ? Palette.yellow
                                : Palette.line,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: compact ? 12 : 14,
                              color: offset.abs() > 0.1
                                  ? Palette.yellow
                                  : Palette.muted,
                            ),
                            SizedBox(width: compact ? 4 : 5),
                            Text(
                              '临时 ${offset >= 0 ? '+' : ''}${offset.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: compact ? 10 : 12,
                                color: offset.abs() > 0.1
                                    ? Palette.yellow
                                    : Palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 3 : 10),
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
                    compact: compact,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        inactiveTrackColor: Palette.line,
                        overlayShape: compact
                            ? const RoundSliderOverlayShape(overlayRadius: 13)
                            : const RoundSliderOverlayShape(overlayRadius: 16),
                      ),
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
                    compact: compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waveforms(int columns, {required bool compact}) {
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
            OutlinedButton.icon(
              onPressed: _importPulse,
              style: compact
                  ? OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
              icon: Icon(Icons.file_open_outlined, size: compact ? 15 : 16),
              label: const Text('导入 .pulse'),
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
      key: _waveformKey(w.id),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: current ? Palette.yellow : Palette.text,
                    ),
                  ),
                ),
                if (w.isCustom)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.upload_file_rounded,
                      size: 14,
                      color: Palette.yellow,
                    ),
                  ),
                if (current)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Palette.yellow,
                    ),
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

class _PulseImportDialog extends StatefulWidget {
  final ControlDesk desk;
  final String source;
  final String initialName;
  const _PulseImportDialog({
    required this.desk,
    required this.source,
    required this.initialName,
  });
  @override
  State<_PulseImportDialog> createState() => _PulseImportDialogState();
}

class _PulseImportDialogState extends State<_PulseImportDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? error;
  bool busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final waveform = await widget.desk.importPulseWaveform(
        widget.source,
        name: _name.text,
      );
      if (mounted) Navigator.pop(context, waveform);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is FormatException ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Palette.surface,
    title: const Text(
      '导入波形',
      style: TextStyle(color: Palette.yellow, fontSize: 20),
    ),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            onSubmitted: busy ? null : (_) => _install(),
            decoration: const InputDecoration(labelText: '波形名称'),
          ),
          if (error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error!,
                style: const TextStyle(color: Palette.yellow, fontSize: 12),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: busy ? null : _install, child: const Text('导入')),
    ],
  );
}

class _RepeatButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onStep;
  final VoidCallback onEnd;
  final bool compact;

  const _RepeatButton({
    required this.tooltip,
    required this.icon,
    required this.onStep,
    required this.onEnd,
    this.compact = false,
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
        child: SizedBox.square(
          dimension: widget.compact ? 36 : 38,
          child: Center(
            child: Material(
              color: Palette.yellow,
              shape: const CircleBorder(),
              child: SizedBox.square(
                dimension: widget.compact ? 28 : 38,
                child: Icon(
                  widget.icon,
                  size: widget.compact ? 16 : 20,
                  color: Palette.background,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
