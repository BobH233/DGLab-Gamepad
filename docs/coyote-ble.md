# Coyote 3 BLE

## Connection

- Scan for BLE devices whose advertised name begins with `47`.
- Main service: `0000180c-0000-1000-8000-00805f9b34fb`.
- Write characteristic: `0000150a-0000-1000-8000-00805f9b34fb`.
- Notify characteristic: `0000150b-0000-1000-8000-00805f9b34fb`.
- Battery service: `0000180a-0000-1000-8000-00805f9b34fb`.
- Battery characteristic: `00001500-0000-1000-8000-00805f9b34fb`.

Android requests a 64-byte ATT MTU after connecting because one Coyote 3 control packet is 21 bytes. iOS and macOS use their system MTU.

## Control Packet

The adapter sends one 21-byte packet every 100ms:

```text
B0  sequence  flags  strengthA  strengthB  pulseA[8]  pulseB[8]
```

- `sequence` is `E` whenever either strength changed, otherwise it advances from `0` to `F`.
- `flags` uses `C` for A, `3` for B, `F` for both, and `0` when unchanged.
- `strengthA/B` are `0..200`.
- Each pulse frame is the currently selected preset’s next 8-byte DG-LAB frame.
- A missing waveform or silence packet uses `0A0A0A0A00000000`.

The device may report `B1` notifications. Bytes 2 and 3 update the displayed device strength for channels A and B.

## Safety

- Connecting starts at zero strength and writes zero before the normal stream.
- Disabled channels, all-stop, entering edit mode, lost gamepad input, app background and script faults produce zero output.
- Active stop and disconnect write a blank waveform with zero strength before closing where the platform permits it.
- Unexpected BLE disconnect stops the local 10Hz sender and clears the selected preview connection.
- Connection is manual on every launch; the app never auto-enables a channel.

The protocol and packet layout are based on the referenced `DG-Lab-Coyote-Game-Hub` commit recorded in [third-party notices](third-party-notices.md). Physical output timing, packet loss, reconnect behavior and battery reporting still require hardware verification on iOS and Android.
