# Coyote 3 BLE

## Connection

- Scan for BLE devices whose advertised name begins with `47`.
- Main service: `0000180c-0000-1000-8000-00805f9b34fb`.
- Write characteristic: `0000150a-0000-1000-8000-00805f9b34fb`.
- Notify characteristic: `0000150b-0000-1000-8000-00805f9b34fb`.
- Battery service: `0000180a-0000-1000-8000-00805f9b34fb`.
- Battery characteristic: `00001500-0000-1000-8000-00805f9b34fb`.

Before scanning, Android requests runtime permissions: `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` on Android 12+, `ACCESS_FINE_LOCATION` on Android 11 and below. Android 12+ scans with `neverForLocation` and does not require the system location switch; older versions still do. Apple platforms prompt through CoreBluetooth on first use.

Android requests a 64-byte ATT MTU after connecting because one Coyote 3 control packet is 20 bytes. iOS and macOS use their system MTU.

## Control Packet

The adapter sends one 20-byte packet every 100ms:

```text
B0  sequence/flags  strengthA  strengthB  pulseA[8]  pulseB[8]
```

- The first nibble cycles through `1..F` only when strength changes; it is `0` otherwise.
- The second nibble uses `C` for A strength, `3` for B strength, `F` for both, and `0` when unchanged.
- `strengthA/B` are `0..200`.
- Each pulse frame is either the selected preset’s next DG-LAB frame or a dynamic frame derived from touch frequency and pulse width.
- A missing waveform or silence packet uses `0A0A0A0A00000000`.
- The control engine publishes `OutputFrame` values independently of BLE state. A separate output waveform trace consumes those frames at the protocol's 100ms timing, while the Coyote adapter only stores the latest frame when disconnected. Active channel cards render the trace as a right-to-left scrolling pulse stream without sending Bluetooth data.

The device reports `B1` notifications. Bytes 2 and 3 update the displayed device strength for channels A and B. After a strength-changing B0 packet, waveform packets continue at 100ms while only further strength changes wait for the matching sequence or a 700ms timeout.

The 100ms cadence is a protocol target, not a hard realtime guarantee from iOS, Android or the BLE stack. Writes are serialized and overlapping packets are skipped instead of being burst later; a delayed platform timer therefore must not cause a catch-up burst of intensity changes.

Touch balance uses `BF` packets with soft limits left unchanged (`201, 201`), the frequency balance written for A/B, and both pulse-width balance bytes set to `0`.

## Safety

- Connecting starts at zero strength and writes zero before the normal stream.
- Disabled channels, all-stop, entering edit mode, lost gamepad input, app background and script faults produce zero output.
- Active stop and disconnect write a blank waveform with zero strength before closing where the platform permits it.
- Unexpected BLE disconnect stops the local 10Hz sender and clears the selected preview connection.
- Connection is manual on every launch; the app never auto-enables a channel.

The protocol and packet layout are based on the referenced `DG-Lab-Coyote-Game-Hub` commit recorded in [third-party notices](third-party-notices.md). Physical output timing, packet loss, reconnect behavior and battery reporting still require hardware verification on iOS and Android.
