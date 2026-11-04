import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ControlStore {
  final File file;
  Future<void> _pending = Future.value();
  ControlStore(this.file);
  static Future<ControlStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return ControlStore(File('${dir.path}/control-profile-v1.json'));
  }

  Future<Map<String, dynamic>?> read() async {
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map || !const {1, 2, 3, 4, 5, 6}.contains(json['version'])) {
      throw const FormatException('配置文件版本不兼容');
    }
    return Map<String, dynamic>.from(json);
  }

  Future<void> save(Map<String, dynamic> value) {
    final serialized = const JsonEncoder.withIndent('  ').convert(value);
    final task = _pending.then((_) async {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(serialized, flush: true);
      await temporary.rename(file.path);
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
}
