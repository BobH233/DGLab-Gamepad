import 'dart:convert';
import 'package:quickjs_engine/quickjs_engine.dart';
import '../control/models.dart';

class ActionRuntime {
  final QuickJsRuntime2 _runtime = QuickJsRuntime2(
    timeout: 10,
    memoryLimit: 8 * 1024 * 1024,
    stackSize: 256 * 1024,
  );
  late final ActionDefinition definition;
  bool _disposed = false;

  ActionRuntime(String source, {bool builtin = false}) {
    try {
      if (utf8.encode(source).length > 65536) {
        throw const FormatException('脚本不能超过 64 KB');
      }
      _evaluate(_bootstrap);
      _evaluate('(function(){"use strict";\n$source\n})();');
      final data =
          jsonDecode(_evaluate('__describe()')) as Map<String, dynamic>;
      _validateDefinition(data, builtin);
      definition = ActionDefinition(data, source, builtin: builtin);
      definition.validateConfig(definition.defaults);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  /// Runs the action. [shared] is a JSON object whose fields are merged into
  /// the context. Callers pass values that rarely change (such as the
  /// waveform list) here, pre-encoded once, instead of re-serializing them on
  /// every event.
  List<dynamic> invoke(Map<String, dynamic> context, {String shared = '{}'}) {
    final result = _evaluate('__dispatch(${jsonEncode(context)},$shared)');
    if (result.length > 16384) throw const FormatException('脚本返回数据过大');
    final decoded = jsonDecode(result);
    if (decoded is! List || decoded.length > 16) {
      throw const FormatException('脚本必须返回最多 16 条指令');
    }
    return decoded;
  }

  void reset() => _evaluate('__reset()');
  String _evaluate(String code) {
    final result = _runtime.evaluate(code);
    if (result.isError) throw FormatException(result.stringResult);
    return result.stringResult;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    JavascriptRuntime.channelFunctionsRegistered.remove(
      _runtime.getEngineInstanceId(),
    );
    _runtime.dispose();
  }

  static void _validateDefinition(Map<String, dynamic> data, bool builtin) {
    if (data['apiVersion'] != 1) {
      throw const FormatException('需要 apiVersion: 1');
    }
    final id = data['id'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_.-]{2,63}$').hasMatch(id) ||
        (!builtin && id.startsWith('builtin.'))) {
      throw const FormatException('操作 ID 无效或使用了内置命名空间');
    }
    if (data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        (data['name'] as String).length > 40) {
      throw const FormatException('操作名称需要 1–40 个字符');
    }
    final inputs = data['inputs'];
    if (inputs is! List ||
        inputs.isEmpty ||
        inputs.length > 3 ||
        inputs.any((v) => !['button', 'trigger', 'stick'].contains(v))) {
      throw const FormatException('输入类型必须为 button / trigger / stick');
    }
    if (data['ticks'] != null && data['ticks'] is! bool) {
      throw const FormatException('ticks 必须是布尔值');
    }
    final fields = data['fields'];
    if (fields is! List || fields.length > 12) {
      throw const FormatException('最多允许 12 个配置项');
    }
    final keys = <String>{};
    for (final field in fields) {
      if (field is! Map ||
          field['key'] is! String ||
          !RegExp(
            r'^[a-zA-Z][a-zA-Z0-9_]{0,31}$',
          ).hasMatch(field['key'] as String) ||
          !keys.add(field['key'] as String)) {
        throw const FormatException('配置项 key 无效或重复');
      }
      if (field['label'] is! String || (field['label'] as String).length > 40) {
        throw const FormatException('配置项缺少名称');
      }
      switch (field['type']) {
        case 'number':
          final min = field['min'], max = field['max'];
          if (min is! num ||
              max is! num ||
              !min.isFinite ||
              !max.isFinite ||
              min > max ||
              min < -10000 ||
              max > 10000) {
            throw const FormatException('数值范围无效');
          }
        case 'select':
          final options = field['options'];
          if (options is! List ||
              options.isEmpty ||
              options.length > 20 ||
              options.any(
                (o) =>
                    o is! Map || o['value'] is! String || o['label'] is! String,
              )) {
            throw const FormatException('选项格式无效');
          }
        case 'waveform':
        case 'waveforms':
          break;
        default:
          throw const FormatException('不支持的配置项类型');
      }
    }
  }
}

const _bootstrap = r'''
(() => {
  const stringify=JSON.stringify.bind(JSON), freeze=Object.freeze;
  for(const name of ['sendMessage','setTimeout','setInterval','fetch','XMLHttpRequest','console','Promise','queueMicrotask','WebAssembly']) {
    Object.defineProperty(globalThis,name,{value:undefined,writable:false,configurable:false});
  }
  let action=null, state={};
  function deepFreeze(value) {
    if(value && typeof value==='object') { Object.keys(value).forEach(k=>deepFreeze(value[k])); freeze(value); }
    return value;
  }
  Object.defineProperty(globalThis,'registerAction',{value:function(value) {
    if(action) throw Error('每个文件只能注册一个操作');
    if(!value || typeof value.onEvent!=='function') throw Error('需要 onEvent(ctx, state)');
    action=value;
  }, writable:false, configurable:false});
  Object.defineProperty(globalThis,'__describe',{value:()=> {
    if(!action) throw Error('未调用 registerAction');
    return stringify({apiVersion:action.apiVersion,id:action.id,name:action.name,inputs:action.inputs,fields:action.fields||[],ticks:action.ticks});
  }});
  Object.defineProperty(globalThis,'__dispatch',{value:(ctx,shared)=> {
    const commands=action.onEvent(deepFreeze(Object.assign(ctx,shared)),state);
    if(!Array.isArray(commands) || commands.length>16) throw Error('onEvent 必须同步返回指令数组');
    const result=stringify(commands);
    if(result.length>16384) throw Error('返回数据过大');
    return result;
  }});
  Object.defineProperty(globalThis,'__reset',{value:()=>{state={};return null;}});
})();
''';
