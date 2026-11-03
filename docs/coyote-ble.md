# Coyote 3 BLE

## Connection

- Scan for BLE devices whose advertised name begins with `47`.
- Main service: `0000180c-0000-1000-8000-00805f9b34fb`.
- Write characteristic: `0000150a-0000-1000-8000-00805f9b34fb`.
- Notify characteristic: `0000150b-0000-1000-8000-00805f9b34fb`.
- Battery service: `0000180a-0000-1000-8000-00805f9b34fb`.
- Battery characteristic: `00001500-0000-1000-8000-00805f9b34fb`.

Android requests a 64-byte ATT MTU after connecting because one Coyote 3 control packet is 20 bytes. iOS and macOS use their system MTU.

## Control Packet

The adapter sends one 20-byte packet every 100ms:

```text
B0  sequence/flags  strengthA  strengthB  pulseA[8]  pulseB[8]
```

- The first nibble is `E` whenever either strength changed, otherwise `0`.
- The second nibble uses `C` for A strength, `3` for B strength, `F` for both, and `0` when unchanged.
- `strengthA/B` are `0..200`.
- Each pulse frame is either the selected preset’s next DG-LAB frame or a dynamic frame derived from touch frequency and pulse width.
- A missing waveform or silence packet uses `0A0A0A0A00000000`.

The device reports `B1` notifications. Bytes 2 and 3 update the displayed device strength for channels A and B. After a strength-changing B0 packet, the stream waits for the matching sequence or a 700ms timeout before sending another strength change.

Touch balance uses `BF` packets with soft limits left unchanged (`201, 201`), the frequency balance written for A/B, and both pulse-width balance bytes set to `0`.

## Safety

- Connecting starts at zero strength and writes zero before the normal stream.
- Disabled channels, all-stop, entering edit mode, lost gamepad input, app background and script faults produce zero output.
- Active stop and disconnect write a blank waveform with zero strength before closing where the platform permits it.
- Unexpected BLE disconnect stops the local 10Hz sender and clears the selected preview connection.
- Connection is manual on every launch; the app never auto-enables a channel.

The protocol and packet layout are based on the referenced `DG-Lab-Coyote-Game-Hub` commit recorded in [third-party notices](third-party-notices.md). Physical output timing, packet loss, reconnect behavior and battery reporting still require hardware verification on iOS and Android.
