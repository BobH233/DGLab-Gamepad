import 'dart:async';

import 'package:flutter/material.dart';

import '../../coyote/coyote_controller.dart';
import '../palette.dart';

Future<void> showCoyoteSheet(
  BuildContext context,
  CoyoteController controller,
) {
  final sheet = showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    builder: (_) => CoyoteSheet(controller: controller),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.connected &&
        !controller.scanning &&
        !controller.connecting) {
      unawaited(controller.scan());
    }
  });
  return sheet;
}

class CoyoteSheet extends StatelessWidget {
  final CoyoteController controller;
  const CoyoteSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bluetooth_rounded, color: Palette.yellow),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '郊狼 3',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (controller.connected)
                  _connected(context)
                else
                  _disconnected(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _connected(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Palette.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.yellow),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Palette.yellow,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.deviceName ?? '郊狼 3',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  controller.batteryLevel == null
                      ? '--%'
                      : '${controller.batteryLevel}%',
                  style: const TextStyle(color: Palette.muted),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _metric('A', controller.deviceStrengthA),
                const SizedBox(width: 12),
                _metric('B', controller.deviceStrengthB),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: controller.disconnect,
          icon: const Icon(Icons.bluetooth_disabled_rounded, size: 18),
          label: const Text('断开连接'),
        ),
      ),
    ],
  );

  Widget _metric(String channel, int strength) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            channel,
            style: const TextStyle(
              color: Palette.yellow,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '$strength',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w300),
          ),
          const Text(' / 200', style: TextStyle(color: Palette.muted)),
        ],
      ),
    ),
  );

  Widget _disconnected() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: controller.status == CoyoteStatus.error
                  ? Palette.yellow
                  : Palette.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(switch (controller.status) {
              CoyoteStatus.scanning => '正在扫描',
              CoyoteStatus.connecting => '正在连接',
              CoyoteStatus.error => controller.error ?? '连接不可用',
              _ => '未连接',
            }, style: const TextStyle(color: Palette.muted, fontSize: 12)),
          ),
          FilledButton.icon(
            onPressed: controller.scanning || controller.connecting
                ? null
                : controller.scan,
            icon: controller.scanning || controller.connecting
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching_rounded, size: 18),
            label: Text(controller.scanning ? '扫描中' : '扫描设备'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (controller.devices.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          decoration: BoxDecoration(
            border: Border.all(color: Palette.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '打开郊狼电源后扫描',
            style: TextStyle(color: Palette.muted, fontSize: 13),
          ),
        )
      else
        for (final device
            in controller.devices.values.toList()
              ..sort((a, b) => b.rssi.compareTo(a.rssi)))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Palette.raised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.sports_esports_rounded,
                color: Palette.yellow,
              ),
              title: Text(device.name),
              subtitle: Text(
                '${device.rssi} dBm',
                style: const TextStyle(color: Palette.muted, fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => controller.connect(device),
            ),
          ),
    ],
  );
}
