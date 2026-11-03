import 'package:flutter/material.dart';

import '../../control/control_desk.dart';
import '../palette.dart';

Future<void> showChannelControlsDialog(
  BuildContext context,
  ControlDesk desk,
  String channel,
) => showDialog<void>(
  context: context,
  builder: (_) => _ChannelControlsDialog(desk: desk, channel: channel),
);

class _ChannelControlsDialog extends StatefulWidget {
  final ControlDesk desk;
  final String channel;

  const _ChannelControlsDialog({required this.desk, required this.channel});

  @override
  State<_ChannelControlsDialog> createState() => _ChannelControlsDialogState();
}

class _ChannelControlsDialogState extends State<_ChannelControlsDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController linear;
  late final TextEditingController boost;
  late String unit;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final channel = widget.desk.engine.state.channels[widget.channel]!;
    linear = TextEditingController(text: _number(channel.linearAmount));
    boost = TextEditingController(text: _number(channel.boostAmount));
    unit = channel.linearUnit;
  }

  @override
  void dispose() {
    linear.dispose();
    boost.dispose();
    super.dispose();
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  String? _amountError(String? text, double min, double max) {
    final value = double.tryParse(text ?? '');
    return value == null || !value.isFinite || value < min || value > max
        ? '请输入 ${min.toStringAsFixed(0)} 至 ${max.toStringAsFixed(0)}'
        : null;
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.desk.setChannelControls(
        widget.channel,
        linearAmount: double.parse(linear.text),
        linearUnit: unit,
        boostAmount: double.parse(boost.text),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Palette.surface,
    title: Text(
      '${widget.channel} 通道控制参数',
      style: const TextStyle(fontSize: 20, color: Palette.yellow),
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '线性扳机',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('linear-unit-${widget.channel}'),
                initialValue: unit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '满行程增减方式'),
                items: const [
                  DropdownMenuItem(value: 'absolute', child: Text('固定数值')),
                  DropdownMenuItem(value: 'percent', child: Text('基础强度百分比')),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => unit = value!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey('linear-amount-${widget.channel}'),
                controller: linear,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '满行程增减量',
                  suffixText: unit == 'percent' ? '%' : null,
                ),
                validator: (value) => _amountError(value, -200, 200),
              ),
              const Divider(height: 34, color: Palette.line),
              const Text(
                '一键开火',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: ValueKey('boost-amount-${widget.channel}'),
                controller: boost,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '开火增量'),
                validator: (value) => _amountError(value, 0, 200),
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Text(
                  error!,
                  style: const TextStyle(color: Palette.yellow, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: saving ? null : _save,
        child: Text(saving ? '保存中' : '保存'),
      ),
    ],
  );
}
