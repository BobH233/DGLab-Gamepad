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

  test(
    'a disconnect during service discovery never reports connected',
    () async {
      transport.openGate = Completer<void>();
      final connecting = controller.connect(device);
      await pumpEventQueue();
      expect(controller.connecting, isTrue);

      transport.emit(
        transport.connections.single,
        DeviceConnectionState.disconnected,
      );
      transport.openGate!.complete();
      await connecting;
      await pumpEventQueue();

      expect(controller.connected, isFalse);
      expect(controller.status, CoyoteStatus.error);
      expect(background, isNot(contains(true)));
      // No sender runs for the dead session.
      final writes = transport.links.single.writes.length;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(transport.links.single.writes.length, writes);
    },
  );

  test(
    'isolated write failures keep the session and resend strength',
    () async {
      await controller.connect(device);
      final link = transport.links.single;
      controller.accept(frame(40));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final failedFrom = link.writes.length;
      link.outcomes.addAll([Exception('GATT busy'), Exception('GATT busy')]);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(controller.connected, isTrue);

      // writes[failedFrom] and [failedFrom + 1] failed; the next packet is
      // the first one the device actually received after them.
      final recovered = link.writes[failedFrom + 2];
      expect(recovered[0], 0xB0);
      // Strength is resent for both channels in case a change was lost.
      expect(recovered[1] & 0x0F, 0x0F);
      expect(recovered[2], 40);
    },
  );

  test('a sustained run of write failures disconnects', () async {
    await controller.connect(device);
    final link = transport.links.single;
    link.outcomes.addAll(
      List.filled(CoyoteController.maxConsecutiveWriteFailures, Exception('x')),
    );
    await Future<void>.delayed(
      coyotePulseIntervalForTest *
          (CoyoteController.maxConsecutiveWriteFailures + 2),
    );
    expect(controller.status, CoyoteStatus.error);
  });

  test('a hung write times out instead of stalling output forever', () async {
    await controller.connect(device);
    final link = transport.links.single;
    link.hold = Completer<void>();
    await Future<void>.delayed(
      CoyoteController.writeTimeout *
              CoyoteController.maxConsecutiveWriteFailures +
          const Duration(milliseconds: 600),
    );
    expect(controller.status, CoyoteStatus.error);
    link.hold!.complete();
  });
}

const coyotePulseIntervalForTest = Duration(milliseconds: 100);
