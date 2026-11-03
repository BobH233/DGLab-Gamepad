import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../control/control_desk.dart';
import '../palette.dart';

class ScriptsPage extends StatefulWidget {
  final ControlDesk desk;
  const ScriptsPage({super.key, required this.desk});
  @override
  State<ScriptsPage> createState() => _ScriptsPageState();
}

class _ScriptsPageState extends State<ScriptsPage> {
  String? error;
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
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '操作脚本',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
                  ),
                  FilledButton.icon(
                    onPressed: _importFile,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('导入 JS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final source = await rootBundle.loadString(
                        'assets/scripts/example.js',
                      );
                      if (context.mounted) {
                        await showDialog<void>(
                          context: context,
                          builder: (_) =>
                              ScriptEditor(desk: widget.desk, source: source),
                        );
                      }
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建脚本'),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Palette.yellow),
                  ),
                ),
              const SizedBox(height: 28),
              for (final builtin in [false, true]) ...[
                Text(
                  builtin ? '内置操作' : '我的操作',
                  style: const TextStyle(color: Palette.yellow, fontSize: 14),
                ),
                const SizedBox(height: 12),
                if (!builtin &&
                    widget.desk.actions.values.every((a) => a.builtin))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '尚未导入脚本',
                      style: TextStyle(color: Palette.muted, fontSize: 13),
                    ),
                  ),
                for (final a in widget.desk.actions.values.where(
                  (a) => a.builtin == builtin,
                ))
                  Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    decoration: BoxDecoration(
                      color: Palette.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.code_rounded,
                        color: Palette.yellow,
                        size: 20,
                      ),
                      title: Text(a.name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        a.id,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Palette.muted,
                        ),
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: '查看脚本',
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => ScriptEditor(
                                desk: widget.desk,
                                source: a.source,
                                readOnly: true,
                              ),
                            ),
                            icon: const Icon(
                              Icons.description_outlined,
                              size: 19,
                            ),
                          ),
                          if (!a.builtin)
                            IconButton(
                              tooltip: '删除脚本及其绑定',
                              onPressed: () async {
                                await widget.desk.uninstall(a.id);
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
              ],
            ],
          ),
        ),
      ),
    ],
  );
  Future<void> _importFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'JavaScript',
            extensions: ['js'],
            uniformTypeIdentifiers: ['com.netscape.javascript-source'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 65536) {
        throw const FormatException('脚本不能超过 64 KB');
      }
      final source = await file.readAsString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => ScriptEditor(desk: widget.desk, source: source),
      );
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }
}

class ScriptEditor extends StatefulWidget {
  final ControlDesk desk;
  final String source;
  final bool readOnly;
  const ScriptEditor({
    super.key,
    required this.desk,
    required this.source,
    this.readOnly = false,
  });
  @override
  State<ScriptEditor> createState() => _ScriptEditorState();
}

class _ScriptEditorState extends State<ScriptEditor> {
  late final TextEditingController controller = TextEditingController(
    text: widget.source,
  );
  String? error;
  bool busy = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Palette.surface,
    title: Text(
      widget.readOnly ? '脚本源码' : '导入操作',
      style: const TextStyle(color: Palette.yellow, fontSize: 20),
    ),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * 0.58,
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: widget.readOnly,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12,
                height: 1.6,
              ),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
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
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: controller.text));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制脚本')));
          }
        },
        child: const Text('复制'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (!widget.readOnly)
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    final definition = widget.desk.validateScript(
                      controller.text,
                    );
                    await widget.desk.install(definition);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加 ${definition.name}')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        error = e.toString();
                        busy = false;
                      });
                    }
                  }
                },
          child: const Text('验证并导入'),
        ),
    ],
  );
}
