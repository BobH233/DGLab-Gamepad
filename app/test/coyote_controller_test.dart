import 'dart:async';

import 'package:dglab_gamepad/control/models.dart';
import 'package:dglab_gamepad/control/output_waveform_trace.dart';
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

  test('only an unexpected drop of a live link reports a loss', () async {
    var losses = 0;
    controller.onUnexpectedDisconnect = () => losses++;

    await controller.connect(device);
    await controller.disconnect();
    expect(losses, 0);

    await controller.connect(device);
    transport.emit(
      transport.connections.last,
      DeviceConnectionState.disconnected,
    );
    await pumpEventQueue();
    expect(losses, 1);
  });

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

  void timingTest(
    String description,
    Future<void> Function(
      WidgetTester,
      CoyoteController,
      FakeTransport,
      OutputWaveformTrace,
    )
    body,
  ) {
    testWidgets(description, (tester) async {
      final transport = FakeTransport();
      final controller = CoyoteController(
        transport: transport,
        setBackgroundActive: (_) async {},
      );
      final trace = OutputWaveformTrace(clock: controller.pulseClock);
      try {
        await body(tester, controller, transport, trace);
      } finally {
        trace.dispose();
        controller.dispose();
      }
    });
  }

  Iterable<(num, num)> values(Iterable<PulseSample> samples) =>
      samples.map((sample) => (sample.frequency, sample.strength));

  timingTest('refresh and ack timeout stay on the shared 100ms clock', (
    tester,
    controller,
    transport,
    trace,
  ) async {
    await controller.connect(device);
    await tester.pump();
    final link = transport.links.single;
    expect(link.writes, hasLength(1));
    controller.accept(frame(40));

    for (var tick = 0; tick < 10; tick++) {
      for (var i = 0; i < 20; i++) {
        controller.flushLatest();
      }
      await tester.pump(const Duration(milliseconds: 99));
      expect(link.writes, hasLength(tick + 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(link.writes, hasLength(tick + 2));
      final packet = link.writes.last;
      expect(
        values(trace.samplesFor('A').skip(tick * 4)),
        values(decodePulseBytes(packet.sublist(4, 12))),
      );
    }
    expect(link.writes.last[2], 40);
    expect(
      link.writes.skip(1).where((packet) => packet[1] >> 4 != 0),
      isNotEmpty,
    );
  });

  timingTest('an unacknowledged strength is retried on a regular tick', (
    tester,
    controller,
    transport,
    trace,
  ) async {
    await controller.connect(device);
    await tester.pump();
    final link = transport.links.single;
    controller.accept(frame(50));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(link.writes, hasLength(17));
    final strengthWrites = link.writes
        .where((packet) => packet[1] >> 4 != 0)
        .toList();
    expect(strengthWrites.length, greaterThanOrEqualTo(3));
    expect(strengthWrites.skip(1).map((packet) => packet[2]), everyElement(50));
  });

  timingTest('offline preview and BLE share phase across a connection', (
    tester,
    controller,
    transport,
    trace,
  ) async {
    controller.accept(frame(60));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(trace.samplesFor('A'), hasLength(20));
    await controller.connect(device);
    await tester.pump();
    final link = transport.links.single;
    link.notifyController.add([0xB1, link.writes.single[1] >> 4, 0, 0]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(link.writes, hasLength(2));
    expect(
      values(decodePulseBytes(link.writes.last.sublist(4, 12))),
      values(trace.samplesFor('A').skip(20)),
    );
    expect(link.writes.last.sublist(4, 12), [
      for (var i = 0; i < 8; i++)
        int.parse(
          waveforms.first.pulseData[5].substring(i * 2, i * 2 + 2),
          radix: 16,
        ),
    ]);
  });

  timingTest('a delayed write skips pulses without a catch-up burst', (
    tester,
    controller,
    transport,
    trace,
  ) async {
    await controller.connect(device);
    await tester.pump();
    final link = transport.links.single;
    controller.accept(frame(40));
    link.hold = Completer<void>();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(link.writes, hasLength(2));
    link.hold!.complete();
    link.hold = null;
    await tester.pump();
    expect(link.writes, hasLength(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(link.writes, hasLength(3));
    expect(
      values(decodePulseBytes(link.writes.last.sublist(4, 12))),
      values(trace.samplesFor('A').skip(12)),
    );
  });

  timingTest('emergency stop writes zero immediately between pulses', (
    tester,
    controller,
    transport,
    trace,
  ) async {
    await controller.connect(device);
    await tester.pump();
    final link = transport.links.single;
    link.notifyController.add([0xB1, link.writes.single[1] >> 4, 0, 0]);
    controller.accept(frame(40));
    await tester.pump(const Duration(milliseconds: 100));
    expect(link.writes.last[2], 40);
    await tester.pump(const Duration(milliseconds: 50));
    await controller.emergencyStop();
    expect(link.writes, hasLength(3));
    expect(link.writes.last.sublist(2, 4), [0, 0]);
    expect(link.writes.last.sublist(4, 12), [10, 10, 10, 10, 0, 0, 0, 0]);
    expect(trace.samplesFor('A'), hasLength(4));
    await tester.pump(const Duration(milliseconds: 50));
    expect(link.writes, hasLength(4));
    expect(link.writes.last.sublist(2, 4), [0, 0]);
    expect(
      trace.samplesFor('A').skip(4),
      everyElement(const PulseSample(10, 0)),
    );
  });
}

const coyotePulseIntervalForTest = Duration(milliseconds: 100);
