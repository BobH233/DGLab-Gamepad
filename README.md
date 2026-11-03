# DG-LAB Gamepad

Flutter 跨 iOS / Android 的手柄控制台，macOS 用于直接调试。当前实现 A/B 双通道抽象控制、可配置按键、真实 JS 操作脚本、输入可视化，以及通过 BLE 向 DG-LAB 郊狼 3 下发强度与波形。IMU 不参与控制。

## 使用

- **控制台**：单击整张 A/B 通道卡片即可选中，设置基础强度、启停、选择波形；显示临时增减与最终强度。停止保留基础值。波形卡片同样是单击应用。
- **按键绑定**：每个按钮、扳机和摇杆独立配置操作。表单由脚本字段自动生成。
- **操作脚本**：查看 9 个内置 JS 操作、导入 `.js` 文件、新建脚本。内置与用户脚本使用相同 API 和运行时。
- **郊狼连接**：控制台状态栏或按键绑定页进入扫描，选择名称以 `47` 开头的 Coyote 3。连接后显示电量与设备回报的 A/B 强度。
- 顶部手柄图标进入原有输入监测页。进入编辑或监测会停止输出；回到控制台后可重新启用。

默认映射：LT/RT 分别给 A/B 临时增加最多 30；LB/RB 分别给 A/B 按住开火 +30；SELECT 切换选中通道；START 启停选中通道；左摇杆渐进调基础强度；右摇杆或方向键移动波形光标；南侧按键应用光标波形。以上均可修改。

例如基础 80、扳机 +80%，全按为 144，半按为 112，松开回到 80。-100% 全按为 0。强度始终限制在 0–200；通道关闭时下发强度为 0。

## 运行

环境：Flutter 3.38.4 / Dart 3.10.3。iOS 15+、Android 24+、macOS 12+。Apple 端 Xcode 27.1；Android 需要 JDK 17、Android SDK 36 及标准 Flutter 工具链。

```sh
flutter --no-version-check pub get
cd app
flutter --no-version-check run -d macos
```

iOS/Android：先在手机系统设置中配对手柄，运行 `flutter devices`，然后在 `app` 执行 `flutter run -d <device-id>`。手柄必须连接运行应用的设备，连接 Mac 不等于连接手机。

如需使用本机代理，可在当前终端设置用户提供的地址；代理不可用时清除变量直接联网：

```sh
export https_proxy=http://127.0.0.1:7897
export http_proxy=http://127.0.0.1:7897
export all_proxy=socks5://127.0.0.1:7897
```

## 测试

测试使用真正的 QuickJS，先编译本机测试动态库。Mac 的 Flutter tester 可能运行 x86_64，因此同时编译两种架构：

```sh
cmake -S vendor/quickjs_engine/native -B build/script-engine \
  -DCMAKE_BUILD_TYPE=Release '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
cmake --build build/script-engine -j6
flutter --no-version-check analyze --no-pub
cd app
LIBQUICKJSC_TEST_PATH="$PWD/../build/script-engine/libquickjs_c_bridge_plugin.dylib" \
  flutter --no-version-check test --no-pub --reporter expanded
flutter --no-version-check build macos --debug --no-pub
```

Flutter 3.38.4 与 Xcode 27.1 的多架构模拟器打包有兼容问题。依赖生成后使用已验证的 arm64 构建命令：

```sh
cd app/ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
```

## 当前验证范围

- 43 项测试：输入层、真实 JS 行为/资源限制、Coyote 3 包编码、DG-LAB 脉冲解码、单次触屏选中、绑定编辑、配置持久化/恢复、手机竖屏与桌面布局通过。
- macOS：原生应用构建及控制台视觉检查通过。此前手柄监测实按由用户确认可用；本次控制台仍需用户完整实按验收。
- iOS：arm64 模拟器构建通过，待真机验证。
- Android：适配源代码已存在；当前机器缺少 SDK/JDK，尚未编译或真机验证。
- 当前优先电脑端功能验收。手机横屏与进一步自适应调整，按用户要求留到下一阶段。

16 个波形预设及其原始 DG-LAB 脉冲帧参考自 `BobH233/DG-Lab-Coyote-Game-Hub`，界面按帧频率与强度绘制脉冲柱形。`OutputSink` 同时更新本地预览与 Coyote BLE 适配器；控制包每 100ms 发送一次，App 进入后台、输入失联、编辑或停止时下发零强度。脚本源码、绑定、基础强度与波形保存在应用支持目录的 `control-profile-v1.json`；启停与临时加成不持久化。

详见 [架构](docs/architecture.md)、[Coyote BLE](docs/coyote-ble.md)、[脚本 API](docs/script-api.md)、[第三方声明](docs/third-party-notices.md)、[已有手柄验证](docs/device-validation.md)。QuickJS 本地补丁和许可证保留于 `vendor/quickjs_engine`。
