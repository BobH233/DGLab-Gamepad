import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../control/models.dart';
import 'coyote_protocol.dart';

enum CoyoteStatus { disconnected, scanning, connecting, connected, error }

class CoyoteScanDevice {
  final String id;
  final String name;
  final int rssi;

  const CoyoteScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

class CoyoteBleException implements Exception {
  final String message;
  const CoyoteBleException(this.message);

  @override
  String toString() => message;
}

class CoyoteController extends ChangeNotifier implements OutputSink {
  FlutterReactiveBle? _ble;
  FlutterReactiveBle get ble => _ble ??= FlutterReactiveBle();

  CoyoteStatus status = CoyoteStatus.disconnected;
  String? error;
  String? deviceId;
  String? deviceName;
  int? batteryLevel;
  int deviceStrengthA = 0;
  int deviceStrengthB = 0;
  final Map<String, CoyoteScanDevice> devices = {};

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  Timer? _scanTimer;
  Timer? _pulseTimer;
  Timer? _batteryTimer;
  Timer? _ackTimer;
  Characteristic? _writeCharacteristic;
  Characteristic? _batteryCharacteristic;
  OutputFrame? _latestFrame;
  CoyotePacketEncoder _encoder = CoyotePacketEncoder();
  bool _forceStrength = false;
  bool _writing = false;
  bool _manualDisconnect = false;
  bool _disposed = false;
  bool _stopPending = false;
  int? _desiredBalanceA;
  int? _desiredBalanceB;
  int? _sentBalanceA;
  int? _sentBalanceB;
  int? _awaitingSequence;

  bool get connected => status == CoyoteStatus.connected;
  bool get scanning => status == CoyoteStatus.scanning;
  bool get connecting => status == CoyoteStatus.connecting;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void accept(OutputFrame frame) {
    _latestFrame = frame;
    _desiredBalanceA = _balance(frame, 'A') ?? _desiredBalanceA;
    _desiredBalanceB = _balance(frame, 'B') ?? _desiredBalanceB;
  }

  Future<void> scan() async {
    if (scanning || connecting || connected) return;
    await _stopScan();
    devices.clear();
    error = null;
    status = CoyoteStatus.scanning;
    _notify();
    try {
      await ble.initialize();
      final adapter = await ble.statusStream
          .where((value) => value != BleStatus.unknown)
          .first
          .timeout(const Duration(seconds: 3));
      if (adapter != BleStatus.ready) {
        throw CoyoteBleException(_adapterMessage(adapter));
      }
      _scanSubscription = ble
          .scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency)
          .listen(
            (device) {
              final name = device.name.trim();
              if (!name.startsWith(coyoteDeviceNamePrefix)) return;
              devices[device.id] = CoyoteScanDevice(
                id: device.id,
                name: name,
                rssi: device.rssi,
              );
              _notify();
            },
            onError: (Object value) {
              _setError('扫描失败：$value');
            },
          );
      _scanTimer = Timer(const Duration(seconds: 8), _stopScan);
    } catch (value) {
      _setError(value is CoyoteBleException ? value.message : '扫描失败：$value');
    }
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (status == CoyoteStatus.scanning) {
      status = CoyoteStatus.disconnected;
      _notify();
    }
  }

  Future<void> connect(CoyoteScanDevice candidate) async {
    if (connecting || connected) return;
    await _stopScan();
    deviceId = candidate.id;
    deviceName = candidate.name;
    error = null;
    status = CoyoteStatus.connecting;
    _notify();
    final ready = Completer<void>();
    _connectionSubscription = ble
        .connectToDevice(
          id: candidate.id,
          servicesWithCharacteristicsToDiscover: {
            Uuid.parse(coyoteMainServiceUuid): [
              Uuid.parse(coyoteWriteCharacteristicUuid),
              Uuid.parse(coyoteNotifyCharacteristicUuid),
            ],
            Uuid.parse(coyoteBatteryServiceUuid): [
              Uuid.parse(coyoteBatteryCharacteristicUuid),
            ],
          },
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !ready.isCompleted) {
              ready.complete();
            } else if (update.connectionState ==
                    DeviceConnectionState.disconnected &&
                !_manualDisconnect) {
              final message = update.failure == null
                  ? '郊狼连接已断开'
                  : '郊狼连接已断开：${update.failure!.message}';
              if (!ready.isCompleted) {
                ready.completeError(CoyoteBleException(message));
              } else {
                _resetConnection(message);
              }
            }
          },
          onError: (Object value) {
            if (!ready.isCompleted) {
              ready.completeError(value);
            } else {
              _resetConnection('连接异常：$value');
            }
          },
        );
    try {
      await ready.future.timeout(const Duration(seconds: 18));
      if (Platform.isAndroid) {
        await ble.requestMtu(deviceId: candidate.id, mtu: 64);
      }
      await ble.discoverAllServices(candidate.id);
      final services = await ble.getDiscoveredServices(candidate.id);
      final mainService = services
          .where(
            (item) => item.id.expanded == Uuid.parse(coyoteMainServiceUuid),
          )
          .firstOrNull;
      final batteryService = services
          .where(
            (item) => item.id.expanded == Uuid.parse(coyoteBatteryServiceUuid),
          )
          .firstOrNull;
      final write = mainService?.characteristics
          .where(
            (item) =>
                item.id.expanded == Uuid.parse(coyoteWriteCharacteristicUuid),
          )
          .firstOrNull;
      final notify = mainService?.characteristics
          .where(
            (item) =>
                item.id.expanded == Uuid.parse(coyoteNotifyCharacteristicUuid),
          )
          .firstOrNull;
      final battery = batteryService?.characteristics
          .where(
            (item) =>
                item.id.expanded == Uuid.parse(coyoteBatteryCharacteristicUuid),
          )
          .firstOrNull;
      if (write == null || notify == null) {
        throw const CoyoteBleException('设备不支持郊狼 3 控制服务');
      }
      _writeCharacteristic = write;
      _batteryCharacteristic = battery;
      _notifySubscription = notify.subscribe().listen(
        _handleNotification,
        onError: (Object value) => _resetConnection('设备通知中断：$value'),
      );
      await _readBattery();
      _encoder = CoyotePacketEncoder();
      _latestFrame = null;
      _forceStrength = true;
      status = CoyoteStatus.connected;
      error = null;
      _pulseTimer = Timer.periodic(
        coyotePulseInterval,
        (_) => unawaited(_sendNext()),
      );
      _batteryTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => unawaited(_readBattery()),
      );
      unawaited(_sendNext());
      _notify();
    } catch (value) {
      await disconnect();
      _setError(value is CoyoteBleException ? value.message : '连接失败：$value');
    }
  }

  Future<void> _sendNext() async {
    final characteristic = _writeCharacteristic;
    if (_writing || characteristic == null || !connected) {
      return;
    }
    _writing = true;
    final force = _forceStrength;
    _forceStrength = false;
    final stop = _stopPending;
    _stopPending = false;
    try {
      final balanceA = _desiredBalanceA;
      final balanceB = _desiredBalanceB;
      if (balanceA != null &&
          balanceB != null &&
          (balanceA != _sentBalanceA || balanceB != _sentBalanceB)) {
        await characteristic.write(
          _encoder.encodeBalance(
            frequencyBalanceA: balanceA,
            frequencyBalanceB: balanceB,
            pulseBalanceA: 0,
            pulseBalanceB: 0,
          ),
          withResponse: false,
        );
        _sentBalanceA = balanceA;
        _sentBalanceB = balanceB;
      }
      final frame = stop ? null : _latestFrame;
      final packet = _encoder.encode(
        frame,
        forceStrength: force,
        silence: stop,
        allowStrengthChange: stop || _awaitingSequence == null,
      );
      final sequence = packet[1] >> 4;
      if (sequence != 0) {
        _awaitingSequence = sequence;
        _ackTimer?.cancel();
        _ackTimer = Timer(const Duration(milliseconds: 700), () {
          _awaitingSequence = null;
          _ackTimer = null;
          unawaited(_sendNext());
        });
      }
      await characteristic.write(packet, withResponse: false);
    } catch (value) {
      _resetConnection('发送失败：$value');
    } finally {
      _writing = false;
      if (_stopPending) unawaited(_sendNext());
    }
  }

  Future<void> emergencyStop() async {
    _latestFrame = null;
    _forceStrength = true;
    _stopPending = true;
    _awaitingSequence = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    if (!_writing) await _sendNext();
  }

  void flushLatest() {
    if (!connected) return;
    _awaitingSequence = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    unawaited(_sendNext());
  }

  void _handleNotification(List<int> value) {
    if (value.length >= 4 && value[0] == 0xB1) {
      deviceStrengthA = value[2].clamp(0, 200);
      deviceStrengthB = value[3].clamp(0, 200);
      if (_awaitingSequence == value[1]) {
        _awaitingSequence = null;
        _ackTimer?.cancel();
        _ackTimer = null;
      }
      _notify();
    }
  }

  Future<void> _readBattery() async {
    final characteristic = _batteryCharacteristic;
    if (characteristic == null) return;
    try {
      final value = await characteristic.read();
      if (value.isNotEmpty) {
        batteryLevel = value.first;
        _notify();
      }
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    final write = _writeCharacteristic;
    if (write != null) {
      try {
        await write.write(
          _encoder.encode(null, forceStrength: true, silence: true),
          withResponse: false,
        );
      } catch (_) {}
    }
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _resetConnection();
    _manualDisconnect = false;
  }

  void _resetConnection([String? message]) {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    _writeCharacteristic = null;
    _batteryCharacteristic = null;
    unawaited(_notifySubscription?.cancel());
    _notifySubscription = null;
    deviceStrengthA = 0;
    deviceStrengthB = 0;
    batteryLevel = null;
    _latestFrame = null;
    _forceStrength = false;
    _desiredBalanceA = null;
    _desiredBalanceB = null;
    _sentBalanceA = null;
    _sentBalanceB = null;
    _awaitingSequence = null;
    status = message == null ? CoyoteStatus.disconnected : CoyoteStatus.error;
    error = message;
    _notify();
  }

  void _setError(String message) {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    status = CoyoteStatus.error;
    error = message;
    _notify();
  }

  String _adapterMessage(BleStatus value) => switch (value) {
    BleStatus.unsupported => '此设备不支持低功耗蓝牙',
    BleStatus.unauthorized => '未获得蓝牙权限',
    BleStatus.poweredOff => '请先打开蓝牙',
    BleStatus.locationServicesDisabled => '请先打开定位服务',
    _ => '蓝牙当前不可用',
  };

  int? _balance(OutputFrame frame, String channel) {
    final value = frame.channels[channel]?['balance'];
    return value is num ? value.round().clamp(0, 255) : null;
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _pulseTimer?.cancel();
    _batteryTimer?.cancel();
    _ackTimer?.cancel();
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_notifySubscription?.cancel());
    super.dispose();
  }
}
