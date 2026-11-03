# 操作脚本 API v1

内置操作与导入操作使用同一个 QuickJS 执行器、配置表单和命令校验器。脚本只计算控制意图，不接触蓝牙、文件、网络或界面。每个绑定有独立运行时和状态；同一个脚本绑定 LT 与 RT 时互不共享变量。

## 注册与配置

一个 UTF-8 `.js` 文件注册一个操作，调用 `registerAction`。可在「操作脚本」中导入文件，或用「新建脚本」编辑。导入校验成功后，在「按键绑定」选择该操作。内置源码可查看，用户脚本可移除；移除会同时解除其绑定。

```js
registerAction({
  apiVersion: 1,
  id: 'user.stepStrength',
  name: '点按调强',
  inputs: ['button'],
  fields: [
    {key: 'target', label: '目标通道', type: 'select', default: 'selected',
     options: [{value: 'selected', label: '当前选中'},
               {value: 'A', label: 'A 通道'}, {value: 'B', label: 'B 通道'}]},
    {key: 'amount', label: '增减量', type: 'number', min: -200, max: 200, default: 5}
  ],
  onEvent(ctx, state) {
    return ctx.event.type === 'press'
      ? [{type: 'adjustBase', channel: ctx.target, value: ctx.config.amount}]
      : [];
  }
});
```

`id` 为 3–64 字符，以英文字母开头，其余可含字母、数字、`_`、`.`、`-`。用户不可使用 `builtin.` 前缀，不可重复 ID。`name` 1–40 字符；`inputs` 为 `button`、`trigger`、`stick` 的非空集合。

最多 12 个 `fields`，每项的 `key` 唯一，`label` 用于表单，`default` 必须符合类型。支持：

| type | 额外字段 | 配置值 |
| --- | --- | --- |
| `number` | `min`, `max`，绝对值不超过 10000 | 有限数字，允许负数和小数 |
| `select` | `options: [{value, label}]`，最多 20 项 | 对应的字符串 value |
| `waveform` | 无 | 现有波形 ID |
| `waveforms` | 无 | 非空波形 ID 数组；顺序决定轮换顺序 |

配置表单自动生成，不需要为每个脚本修改 Flutter。宿主只传入已声明、通过校验的字段。若定义 `target` 配置为 `A/B/selected`，宿主会计算 `ctx.target`；未定义或值为 selected 时默认使用当前选中通道。

## 输入

`onEvent(ctx, state)` 必须**同步返回指令数组**。不接受 Promise。`ctx` 深度冻结；`state` 是该绑定的可变临时对象，取消操作时重建为空对象。不要依赖全局变量在取消后自动重置；需要重置的变量一律放 `state`。无事件需处理时返回 `[]`。

| ctx 字段 | 内容 |
| --- | --- |
| `apiVersion`, `bindingId` | `1`、当前绑定 ID |
| `event` | 下表中的事件对象 |
| `config` | 校验后的配置 |
| `target`, `selected` | 本次解析的目标、当前选中通道，均为 A/B |
| `channels.A/B` | `base`, `enabled`, `waveform`, `cursor`, `effective` |
| `input` | 按钮/扳机 `{value: 0..1}`；摇杆 `{x: -1..1, y: -1..1}` |
| `touch` | `{open, surface, channel, point}`；触控面板状态和当前归一化触点 |
| `waveforms` | `[{id, name}, ...]`，与界面顺序一致 |
| `grid` | `{columns, count}`，当前响应式波形网格 |
| `random` | 本次调用提供的 `[0,1)` 随机数 |

`effective` 为限幅后的计算强度，即使通道停止也可读；实际输出帧在停止时强度为零。`enabled` 包含临时启停覆盖。X 右正左负，Y 下正上负；摇杆已通过输入层径向死区处理。

| event | 触发条件 |
| --- | --- |
| `{type:'press', value}` | 按钮按下边沿 |
| `{type:'release', value}` | 按钮松开边沿 |
| `{type:'value', value}` | 线性扳机值发生变化 |
| `{type:'tick', dt}` | 活跃输入期间约 20Hz，dt 为秒，最大 0.1 |

所有绑定接收 tick，脚本应忽略无关事件。摇杆在 tick 中读取向量。按钮重复由脚本用 dt 实现，宿主不会把保持状态重复当作 press。`touch.surface` 只在触控区域显示时为真，进入触控设置后为假，脚本不应在设置页继续产生触点。

扳机绑定 `button` 操作时进入阈值模式：默认 0.55，可选 0.15–0.95；按下阈值为设置值，松开阈值比其低 0.1，避免阈值附近抖动。同时支持 trigger 和 button 的脚本优先接收连续 value。

## 输出命令

一次调用最多 16 条命令，总 JSON 长度最多 16384 字符。每个数组先在草稿状态上完整校验，全部通过后统一提交；失败不会提交半个数组。除 `clearOverlay` 和 `touchPoint` 外，所有命令必须包含 `channel: 'A' | 'B'`。

| type | 其他参数 | 效果 |
| --- | --- | --- |
| `offset` | `value: -200..200`, `unit: absolute/percent` | 设置该绑定的临时强度增减 |
| `enableOverlay` | `value: boolean` | 设置该绑定的临时启停状态 |
| `clearOverlay` | 无 | 清除此绑定的临时效果 |
| `toggleEnabled` | 无 | 切换通道基础启停状态，保留基础强度 |
| `adjustBase` | `value: -200..200` | 累加基础强度，再限幅至 0–200 |
| `setBase` | `value: 0..200` | 设置基础强度 |
| `selectChannel` | 无 | 改变当前选中通道 |
| `waveform` | `id: waveformId` | 应用波形，并将光标移动至该波形 |
| `moveCursor` | `direction: up/down/left/right` | 移动目标通道光标，不立即改变波形 |
| `applyCursor` | 无 | 应用目标通道光标所在波形 |
| `touchPoint` | `x: 0..1`, `y: 0..1`, `active: boolean` | 更新当前触控面板触点；隐藏设置页时忽略 |

每个绑定有**一个临时效果槽位**，offset/enableOverlay 会替换同一绑定之前的效果；不同绑定的强度效果相加。多个启停覆盖以最近设置的为准；移除后露出其余覆盖或基础状态。持久启停命令修改基础状态，不覆盖仍按住的临时效果。

强度计算：

```
临时增减 = Σ 固定增减 + 基础强度 × Σ 百分比 / 100
计算强度 = clamp(基础强度 + 临时增减, 0, 200)
输出强度 = enabled ? round(计算强度) : 0
```

百分比永远基于基础强度，不把其他临时加成作为下一次计算的基数。80 基础强度、+80% 满扳机时输出 144；半扳机输出 112；松开回到 80。-100% 满扳机为 0。

## 内置行为

- **一键开火**：固定增量；按住/松开或再次点按撤销。激活时锁定目标，期间切换选中通道不会把未松开的加成转移。
- **线性强度**：固定值或百分比 × 扳机行程。允许负值。行程回到 0.01 以下清除效果；重新按压重新解析目标。
- **选择通道**：指定 A、指定 B、A/B 轮换。
- **启停通道**：持久点按切换；或者按住时反转当时有效状态，松开移除临时覆盖。
- **切换波形**：指定、列表顺序轮换、随机选择。随机可重复抽中当前波形。
- **移动光标/应用波形**：方向键按下立即移动，保持 0.4 秒后每 0.14 秒重复；确认键应用光标位置。
- **摇杆渐进调强**：竖直方向调基础强度，速率从 3 到 30 单位/秒，在 2 秒内增长，并乘以 `abs(y)^1.5`。回中立即停止；反向重新加速。目标在持续同向操作期间锁定。没有松手后继续变化的滑行。
- **摇杆移动光标**：触控面板打开时，摇杆向量映射到面板上的归一化落点；中心回中释放触点，斜向满行程可到面板角落。触控面板关闭时，主轴决定波形光标方向，阈值 0.35，重复节奏同方向键。

屏幕手指触点与脚本触点共用 `ControlState`。手指未抬起时脚本触点命令会被忽略；抬起后，活动的摇杆绑定可在下一次 tick 接管。同一时刻一个绑定的 `touchPoint` 保持触点所有权，其他绑定需等它发送 `active:false` 后才能接管。

## 生命周期与资源边界

断开、断流、后台、编辑绑定、切换到监测页、全部停止都会清除瞬时状态；停止保留基础强度和波形，禁用通道输出。恢复输入先要求所有键回中。脚本异常会记录错误、停用该绑定并停止两路；修改/重新保存绑定会重新创建运行时并清除错误。

每个运行时 QuickJS 堆上限 8 MiB、JS 栈上限 256 KiB、每次求值原生中断预算 10ms；文件最大 64 KiB，用户脚本最多 32 个，绑定最多 24 个。没有网络、文件、原生消息、模块加载、定时器 API；不运行 JS 异步任务队列。限额是应用层资源约束，不是操作系统级隔离，也不保证实时设备截止时间。

依赖 `quickjs_engine 0.1.6` 的本地源码副本。上游的 Dart timeout 参数未被 C++ 实现接收，本项目补齐了 QuickJS 中断预算；macOS 改为源码编译确保补丁实际生效。见 `vendor/quickjs_engine/LOCAL_PATCHES.md`。更新依赖必须重新运行无限循环、内存上限、命令事务和界面测试。

## 持久化与未来设备适配

应用支持目录 `control-profile-v1.json` 保存绑定、导入的脚本源码、两路基础强度和波形。使用串行写入及临时文件替换；持续调强每约 600ms 保存一次。启停状态、临时效果、脚本 state 和输入状态不保存；重启默认停止。异常配置以提示显示，非法绑定被跳过。

输出通过 `OutputSink.accept(OutputFrame)` 发布版本化、只读的两路快照：

```json
{"version":1,"sequence":42,"channels":{
  "A":{"intensity":80,"enabled":true,"waveformId":"d6f83af0"},
  "B":{"intensity":0,"enabled":false,"waveformId":"eea0e4ce"}
}}
```

`OutputFrame` 同时进入本地预览与 Coyote 3 BLE 适配器；脚本仍不能直接访问蓝牙。适配器负责连接、协议编码、100ms 发送节流、设备强度通知和断连处理。当前 16 个波形预设的 ID、名称和原始脉冲帧参考自 `BobH233/DG-Lab-Coyote-Game-Hub`；界面用这些帧的频率与强度绘制脉冲柱形。
