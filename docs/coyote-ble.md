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

- The first nibble is always `0`: absolute strength writes do not request acknowledgements.
- The second nibble uses `C` for A strength, `3` for B strength, `F` for both, and `0` when unchanged.
- `strengthA/B` are `0..200`.
- Each pulse frame is either the selected preset’s next DG-LAB frame or a dynamic frame derived from touch frequency and pulse width.
- A missing waveform or silence packet uses `0A0A0A0A00000000`.
- The control engine publishes `OutputFrame` values independently of BLE state. A single `OutputPulseClock` advances both channels every 100ms and supplies the same immutable pulse snapshot to the waveform trace and connected BLE sender. Preview continues while disconnected. Encoding, refreshing controls and stopping do not independently advance waveform phase.

Received `B1` notifications update the last reported device strengths from bytes 2 and 3. They never gate subsequent output. All strength changes use absolute values and sequence `0`, the protocol's no-acknowledgement mode; new strengths and touch values are sent on the next available 100ms tick even if no `B1` arrives. Sequence `0` does not request strength feedback, so displayed device reports may not reflect every app-driven change and are not proof of delivery. There is no 700ms acknowledgement timer.

The 100ms cadence is a protocol target, not a hard realtime guarantee from iOS, Android or the BLE stack. Normal writes are serialized and overlapping packets are skipped instead of being burst later; a delayed platform timer therefore must not cause a catch-up burst of intensity changes. A pulse that becomes obsolete while a balance write is pending is discarded. Ordinary refreshes wait for the shared tick; emergency stop and disconnect can send an immediate zero-strength blank packet without advancing waveform phase.

Touch balance uses `BF` packets with soft limits left unchanged (`201, 201`), the frequency balance written for A/B, and both pulse-width balance bytes set to `0`.

## Safety

- Connecting starts at zero strength and writes zero before the normal stream.
- Disabled channels, all-stop, entering edit mode, lost gamepad input and script faults produce zero output. Backgrounding clears touch input and temporary overlays but preserves enabled channels and their base output; background input inactivity alone is not treated as a lost gamepad.
- Active stop and disconnect write a blank waveform with zero strength before closing where the platform permits it.
- Unexpected BLE disconnect stops the local 10Hz sender and disables both channels, keeping their base strengths. Reconnecting therefore never resumes output on its own.
- Each output write, including the final disconnect stop, has a 400ms timeout. A single failed or timed-out write keeps the session and forces absolute strengths on the next packet; five consecutive failures end the session.
- Connection is manual on every launch; the app never auto-enables a channel.
- Android keeps the link alive with a `connectedDevice` foreground service while connected. Home and Back both leave output running in the background. Removing the task from recents stops the service; activity destruction also stops it alongside its owning engine (`stopWithTask="true"`, `START_NOT_STICKY`).
- iOS keeps the process running in the background with a silent, mixable audio session (`UIBackgroundModes` `audio`), started on connect and deactivated on disconnect. The session is configured with `mixWithOthers` before any audio engine/player graph is created, including after a media-services reset. The keep-alive does not publish Now Playing metadata or configure remote media commands. Coexistence must still be verified on a physical device (start music first, then connect, disconnect/reconnect, and background the app). Registration follows the implicit UIScene engine lifecycle. `bluetooth-central` alone only wakes the app for BLE events and cannot drive the 10Hz sender.
- iOS can take the audio session away (calls, Siri, alarms, media-services resets, route changes). `SilentAudioKeepAlive` tracks `idle` / `running` / `interrupted` and recovers on every signal that the session may be usable again: interruption end (with or without `shouldResume`), media-services reset (the engine is rebuilt), engine configuration and route changes, and the app becoming active. Apple does not guarantee an interruption-end notification, so failed recoveries also retry with backoff (1s doubling to 30s; 8s after an interruption begins). While interrupted, a UIKit background task holds the app for the system-granted grace period so short interruptions do not suspend the BLE sender. Long interruptions can still suspend the app; output resumes when the session recovers.
- The keep-alive state is pushed to Dart. While connected and interrupted, the control screen warns that background output may pause. Process termination by the system cannot be recovered from in-app.

The protocol and packet layout are based on the referenced `DG-Lab-Coyote-Game-Hub` commit recorded in [third-party notices](third-party-notices.md). Physical output timing, packet loss, reconnect behavior and battery reporting still require hardware verification on iOS and Android.
