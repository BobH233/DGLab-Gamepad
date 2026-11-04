import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../control/models.dart';
import '../platform/background_runtime.dart';
import '../platform/bluetooth_permissions.dart';
import 'coyote_protocol.dart';
import 'coyote_transport.dart';

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
  CoyoteController({
    CoyoteTransport? transport,
    Future<BluetoothPermissionState> Function()? requestPermissions,
    Future<void> Function(bool connected)? setBackgroundActive,
  }) : _transport = transport ?? ReactiveBleCoyoteTransport(),
       _requestPermissions = requestPermissions ?? BluetoothPermissions.request,
       _setBackgroundActive =
           setBackgroundActive ?? BackgroundRuntime.setBleConnected;

  final CoyoteTransport _transport;
  final Future<BluetoothPermissionState> Function() _requestPermissions;
  final Future<void> Function(bool connected) _setBackgroundActive;

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
  CoyoteLink? _link;
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

  /// Incremented whenever a connection attempt starts or the link is torn
  /// down. An async step in [connect] that resumes under a different value
  /// belongs to a session that no longer exists.
  int _session = 0;

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
      final permissions = await _requestPermissions();
      if (!permissions.granted) {
        throw const CoyoteBleException('未获得蓝牙权限，请在系统设置中允许“附近设备”权限');
      }
      final adapter = await _transport.adapterStatus();
      // The plugin caches its status stream, so an "unauthorized" value can
      // be stale right after the user grants permission on Android.
      final staleUnauthorized =
          adapter == BleStatus.unauthorized && Platform.isAndroid;
      if (adapter != BleStatus.ready && !staleUnauthorized) {
        throw CoyoteBleException(_adapterMessage(adapter));
      }
      _scanSubscription = _transport
          .scan(requireLocationServices: permissions.locationServicesRequired)
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
    final session = ++_session;
    bool stale() => _disposed || session != _session;
    final ready = Completer<void>();
    _connectionSubscription = _transport
        .connect(candidate.id)
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
      if (stale()) return;
      final link = await _transport.open(candidate.id);
      if (stale()) return;
      if (link == null) {
        throw const CoyoteBleException('设备不支持郊狼 3 控制服务');
      }
      _link = link;
      _notifySubscription = link.notifications().listen(
        _handleNotification,
        onError: (Object value) => _resetConnection('设备通知中断：$value'),
      );
      await _readBattery();
      if (stale()) return;
      await _setBackgroundActive(true);
      if (stale()) {
        // The reset that invalidated this session may have released the
        // keep-alive before this request finished; release it again.
        await _setBackgroundActive(false);
        return;
      }
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
      if (stale()) return;
      await disconnect();
      _setError(value is CoyoteBleException ? value.message : '连接失败：$value');
    }
  }

  Future<void> _sendNext() async {
    final link = _link;
    if (_writing || link == null || !connected) {
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
        await link.write(
          _encoder.encodeBalance(
            frequencyBalanceA: balanceA,
            frequencyBalanceB: balanceB,
            pulseBalanceA: 0,
            pulseBalanceB: 0,
          ),
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
      await link.write(packet);
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
    final link = _link;
    if (link == null) return;
    try {
      final value = await link.readBattery();
      if (value != null && value.isNotEmpty) {
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
    final link = _link;
    if (link != null) {
      try {
        await link.write(
          _encoder.encode(null, forceStrength: true, silence: true),
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
    _session++;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    _link = null;
    unawaited(_notifySubscription?.cancel());
    _notifySubscription = null;
    // Cancelling the connection stream is what tears the GATT link down in
    // flutter_reactive_ble. Leaving it open leaks the old connection, and its
    // late events could reset a newer session.
    unawaited(_connectionSubscription?.cancel());
    _connectionSubscription = null;
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
    unawaited(_setBackgroundActive(false));
    _notify();
  }

  void _setError(String message) {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    status = CoyoteStatus.error;
    error = message;
    unawaited(_setBackgroundActive(false));
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
    unawaited(_setBackgroundActive(false));
    super.dispose();
  }
}
