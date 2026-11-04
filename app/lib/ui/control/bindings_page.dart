import 'package:flutter/material.dart';
import '../../control/control_desk.dart';
import '../../control/models.dart';
import '../palette.dart';

class BindingsPage extends StatelessWidget {
  final ControlDesk desk;
  const BindingsPage({super.key, required this.desk});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '每个按键，由你定义',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
                  ),
                  OutlinedButton.icon(
                    onPressed: desk.resetBindings,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('恢复默认'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              for (final kind in ['trigger', 'button', 'stick']) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  child: Text(
                    switch (kind) {
                      'trigger' => '线性扳机',
                      'stick' => '摇杆',
                      _ => '按键',
                    },
                    style: const TextStyle(color: Palette.yellow, fontSize: 14),
                  ),
                ),
                for (final entry in inputLabels.entries.where(
                  (e) => inputKind(e.key) == kind,
                ))
                  _row(context, entry.key, entry.value),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    ],
  );
  Widget _row(BuildContext context, String input, String label) {
    final matches = desk.bindings.where((b) => b.input == input);
    final binding = matches.isEmpty ? null : matches.first;
    final action = binding == null ? null : desk.actions[binding.action];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Palette.yellow, fontSize: 13),
          ),
        ),
        title: Text(
          action?.name ?? '未绑定',
          style: TextStyle(
            fontSize: 14,
            color: action == null ? Palette.muted : Palette.text,
          ),
        ),
        subtitle: binding == null
            ? null
            : Text(
                _summary(binding),
                style: const TextStyle(fontSize: 11, color: Palette.muted),
              ),
        trailing: Icon(
          desk.engine.errors.containsKey(binding?.id)
              ? Icons.error_outline
              : Icons.chevron_right,
          color: Palette.muted,
          size: 20,
        ),
        onTap: () async {
          await showDialog<void>(
            context: context,
            builder: (_) =>
                BindingEditor(desk: desk, input: input, binding: binding),
          );
        },
      ),
    );
  }

  String _summary(Binding b) {
    final target = switch (b.config['target']) {
      'A' => 'A 通道',
      'B' => 'B 通道',
      'selected' => '当前选中通道',
      _ => '',
    };
    final amount = b.config['amount'];
    final parts = [
      if (target.isNotEmpty) target,
      if (amount != null)
        '${(amount as num) >= 0 ? '+' : ''}$amount${b.config['unit'] == 'percent' ? '%' : ''}',
      if (b.config['mode'] == 'hold') '按住生效',
      if (b.config['mode'] == 'toggle') '点按切换',
      if (inputKind(b.input) == 'trigger' &&
          !(desk.actions[b.action]?.inputs.contains('trigger') ?? false))
        '触发阈值 ${(b.threshold * 100).round()}%',
    ];
    return parts.isEmpty ? '已配置' : parts.join(' · ');
  }
}

class BindingEditor extends StatefulWidget {
  final ControlDesk desk;
  final String input;
  final Binding? binding;
  const BindingEditor({
    super.key,
    required this.desk,
    required this.input,
    this.binding,
  });
  @override
  State<BindingEditor> createState() => _BindingEditorState();
}

class _BindingEditorState extends State<BindingEditor> {
  String? actionId;
  Map<String, dynamic> config = {};
  double threshold = 0.55;
  bool saving = false;
  String? error;
  final form = GlobalKey<FormState>();
  ActionDefinition? get action => widget.desk.actions[actionId];
  @override
  void initState() {
    super.initState();
    actionId = widget.binding?.action;
    config = Map.from(widget.binding?.config ?? {});
    threshold = widget.binding?.threshold ?? 0.55;
  }

  @override
  Widget build(BuildContext context) {
    final kind = inputKind(widget.input);
    final candidates = widget.desk.actions.values
        .where(
          (a) =>
              a.inputs.contains(kind) ||
              (kind == 'trigger' && a.inputs.contains('button')),
        )
        .toList();
    return AlertDialog(
      backgroundColor: Palette.surface,
      title: Text(
        '${inputLabels[widget.input]} · 操作绑定',
        style: const TextStyle(fontSize: 20, color: Palette.yellow),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: actionId,
                  decoration: const InputDecoration(labelText: '操作'),
                  isExpanded: true,
                  items: [
                    for (final a in candidates)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (id) => setState(() {
                    actionId = id;
                    config = Map.from(action!.defaults);
                    error = null;
                  }),
                ),
                if (action != null) ...[
                  const SizedBox(height: 18),
                  for (final field in action!.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _field(field),
                    ),
                  if (kind == 'trigger' &&
                      !action!.inputs.contains('trigger')) ...[
                    Text(
                      '按钮触发阈值  ${(threshold * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.yellow,
                      ),
                    ),
                    Slider(
                      value: threshold,
                      min: 0.15,
                      max: 0.95,
                      divisions: 16,
                      label: '${(threshold * 100).round()}%',
                      onChanged: (v) => setState(() => threshold = v),
                    ),
                  ],
                ],
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Palette.yellow, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.binding != null)
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    await widget.desk.removeBinding(widget.binding!.id);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('解除绑定'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: action == null || saving ? null : _save,
          child: Text(saving ? '保存中' : '保存'),
        ),
      ],
    );
  }

  Widget _field(Map<String, dynamic> field) {
    final key = field['key'] as String,
        label = field['label'] as String,
        type = field['type'];
    final value = config[key] ?? field['default'];
    switch (type) {
      case 'number':
        return TextFormField(
          key: ValueKey('$actionId.$key'),
          initialValue: '$value',
          decoration: InputDecoration(
            labelText: label,
            suffixText: field['key'] == 'amount' && config['unit'] == 'percent'
                ? '%'
                : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          validator: (text) {
            final n = double.tryParse(text ?? '');
            return n == null ||
                    !n.isFinite ||
                    n < (field['min'] as num) ||
                    n > (field['max'] as num)
                ? '请输入 ${field['min']} 至 ${field['max']}'
                : null;
          },
          onChanged: (text) {
            config[key] = double.tryParse(text);
          },
        );
      case 'select':
        return DropdownButtonFormField<String>(
          key: ValueKey('$actionId.$key'),
          initialValue: value as String,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final o in field['options'] as List)
              DropdownMenuItem(
                value: o['value'] as String,
                child: Text(o['label'] as String),
              ),
          ],
          onChanged: (v) => setState(() => config[key] = v),
        );
      case 'waveform':
        return DropdownButtonFormField<String>(
          key: ValueKey('$actionId.$key'),
          initialValue: value as String,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final w in waveforms)
              DropdownMenuItem(value: w.id, child: Text(w.name)),
          ],
          onChanged: (v) => setState(() => config[key] = v),
        );
      case 'waveforms':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final w in waveforms)
                  FilterChip(
                    label: Text(w.name),
                    selected: (value as List).contains(w.id),
                    onSelected: (selected) => setState(() {
                      final list = List<String>.from(value);
                      if (selected) {
                        list.add(w.id);
                      } else {
                        list.remove(w.id);
                      }
                      config[key] = list;
                    }),
                  ),
              ],
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final valid = action!.validateConfig(config);
      await widget.desk.setBinding(
        Binding(
          id: widget.binding?.id ?? 'bind_${widget.input}',
          input: widget.input,
          action: actionId!,
          config: valid,
          threshold: threshold,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          saving = false;
        });
      }
    }
  }
}
