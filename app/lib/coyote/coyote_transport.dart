import 'dart:async';
import 'dart:io';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'coyote_protocol.dart';

/// A resolved Coyote 3 GATT session: the characteristics the controller
/// talks to once a device is connected and its services are discovered.
abstract interface class CoyoteLink {
  Future<void> write(List<int> value);
  Stream<List<int>> notifications();

  /// Reads the battery level, or returns null if the device has no battery
  /// characteristic.
  Future<List<int>?> readBattery();
}

/// The BLE operations [CoyoteController] needs. Kept narrow so the
/// connection state machine can be tested without a radio.
abstract interface class CoyoteTransport {
  Future<BleStatus> adapterStatus();
  Stream<DiscoveredDevice> scan({required bool requireLocationServices});
  Stream<ConnectionStateUpdate> connect(String deviceId);

  /// Negotiates MTU (where needed) and discovers services. Returns null if
  /// the device does not expose the Coyote 3 control service.
  Future<CoyoteLink?> open(String deviceId);
}

class ReactiveBleCoyoteTransport implements CoyoteTransport {
  FlutterReactiveBle? _ble;
  FlutterReactiveBle get _client => _ble ??= FlutterReactiveBle();

  static final _mainService = Uuid.parse(coyoteMainServiceUuid);
  static final _batteryService = Uuid.parse(coyoteBatteryServiceUuid);
  static final _writeCharacteristic = Uuid.parse(coyoteWriteCharacteristicUuid);
  static final _notifyCharacteristic = Uuid.parse(
    coyoteNotifyCharacteristicUuid,
  );
  static final _batteryCharacteristic = Uuid.parse(
    coyoteBatteryCharacteristicUuid,
  );

  @override
  Future<BleStatus> adapterStatus() async {
    await _client.initialize();
    return _client.statusStream
        .where((value) => value != BleStatus.unknown)
        .first
        .timeout(const Duration(seconds: 3));
  }

  @override
  Stream<DiscoveredDevice> scan({required bool requireLocationServices}) =>
      _client.scanForDevices(
        withServices: const [],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: requireLocationServices,
      );

  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) =>
      _client.connectToDevice(
        id: deviceId,
        servicesWithCharacteristicsToDiscover: {
          _mainService: [_writeCharacteristic, _notifyCharacteristic],
          _batteryService: [_batteryCharacteristic],
        },
        connectionTimeout: const Duration(seconds: 15),
      );

  @override
  Future<CoyoteLink?> open(String deviceId) async {
    // iOS and macOS negotiate MTU automatically; Android starts at 23 bytes,
    // which only just fits a 20-byte B0 packet.
    if (Platform.isAndroid) {
      await _client.requestMtu(deviceId: deviceId, mtu: 64);
    }
    await _client.discoverAllServices(deviceId);
    final services = await _client.getDiscoveredServices(deviceId);
    Characteristic? find(Uuid service, Uuid characteristic) => services
        .where((item) => item.id.expanded == service)
        .firstOrNull
        ?.characteristics
        .where((item) => item.id.expanded == characteristic)
        .firstOrNull;
    final write = find(_mainService, _writeCharacteristic);
    final notify = find(_mainService, _notifyCharacteristic);
    if (write == null || notify == null) return null;
    return _ReactiveBleLink(
      write,
      notify,
      find(_batteryService, _batteryCharacteristic),
    );
  }
}

class _ReactiveBleLink implements CoyoteLink {
  final Characteristic _write;
  final Characteristic _notify;
  final Characteristic? _battery;
  _ReactiveBleLink(this._write, this._notify, this._battery);

  @override
  Future<void> write(List<int> value) =>
      _write.write(value, withResponse: false);

  @override
  Stream<List<int>> notifications() => _notify.subscribe();

  @override
  Future<List<int>?> readBattery() async => _battery?.read();
}
