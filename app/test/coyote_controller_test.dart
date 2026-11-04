import 'dart:async';

import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/coyote/coyote_controller.dart';
import 'package:dglab_gamepad/coyote/coyote_transport.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLink implements CoyoteLink {
  final writes = <List<int>>[];
  final notifyController = StreamController<List<int>>.broadcast();

  /// When set, the next writes complete with these results in order.
  final List<Object?> outcomes = [];
  Completer<void>? hold;

  @override
  Future<void> write(List<int> value) async {
    writes.add(List.of(value));
    if (hold != null) await hold!.future;
    if (outcomes.isNotEmpty) {
      final outcome = outcomes.removeAt(0);
      if (outcome != null) throw outcome;
    }
  }

  @override
  Stream<List<int>> notifications() => notifyController.stream;

  @override
  Future<List<int>?> readBattery() async => [87];
}

class FakeTransport implements CoyoteTransport {
  final connections = <StreamController<ConnectionStateUpdate>>[];
  final links = <FakeLink>[];
  Completer<void>? openGate;

  @override
  Future<BleStatus> adapterStatus() async => BleStatus.ready;

  @override
  Stream<DiscoveredDevice> scan({required bool requireLocationServices}) =>
      const Stream.empty();

  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) {
    final controller = StreamController<ConnectionStateUpdate>();
    connections.add(controller);
    scheduleMicrotask(() => emit(controller, DeviceConnectionState.connected));
    return controller.stream;
  }

  void emit(
    StreamController<ConnectionStateUpdate> controller,
    DeviceConnectionState state,
  ) {
    if (controller.isClosed || !controller.hasListener) return;
    controller.add(
      ConnectionStateUpdate(
        deviceId: 'coyote',
        connectionState: state,
        failure: null,
      ),
    );
  }

  @override
  Future<CoyoteLink?> open(String deviceId) async {
    if (openGate != null) await openGate!.future;
    final link = FakeLink();
    links.add(link);
    return link;
  }
}

const device = CoyoteScanDevice(id: 'coyote', name: '47L121000', rssi: -40);

OutputFrame frame(int intensityA) => OutputFrame(1, {
  'A': {
    'intensity': intensityA,
    'enabled': intensityA > 0,
    'waveformId': waveforms.first.id,
  },
  'B': {'intensity': 0, 'enabled': false, 'waveformId': waveforms.first.id},
});

void main() {
  late FakeTransport transport;
  late List<bool> background;
  late CoyoteController controller;

  setUp(() {
    transport = FakeTransport();
    background = [];
    controller = CoyoteController(
      transport: transport,
      requestPermissions: () async =>
          (granted: true, locationServicesRequired: false),
      setBackgroundActive: (value) async => background.add(value),
    );
  });

  tearDown(() => controller.dispose());

  test('unexpected disconnect releases the connection stream', () async {
    await controller.connect(device);
    expect(controller.connected, isTrue);
    final first = transport.connections.single;

    transport.emit(first, DeviceConnectionState.disconnected);
    await pumpEventQueue();

    expect(controller.status, CoyoteStatus.error);
    expect(first.hasListener, isFalse);
    expect(background.last, isFalse);
  });

  test('a stale disconnect cannot reset a newer session', () async {
    await controller.connect(device);
    final first = transport.connections.single;
    transport.emit(first, DeviceConnectionState.disconnected);
    await pumpEventQueue();

    await controller.connect(device);
    expect(controller.connected, isTrue);

    transport.emit(first, DeviceConnectionState.disconnected);
    await pumpEventQueue();
    expect(controller.connected, isTrue);
  });
}
