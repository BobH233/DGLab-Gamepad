import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var orientationChannel: FlutterMethodChannel?
  private var backgroundChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // With UIScene the engine is created by the scene's FlutterViewController,
  // after didFinishLaunching. Plugins and app channels must be registered here.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "dglab_gamepad/display_orientation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "navigationSide" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.navigationSide())
    }
    orientationChannel = channel

    // Keep the process running in the background only while a Coyote is
    // connected, mirroring the Android foreground service.
    let background = FlutterMethodChannel(
      name: "dglab_gamepad/background_runtime",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    background.setMethodCallHandler { call, result in
      let keepAlive = SilentAudioKeepAlive.shared
      switch call.method {
      case "setBleConnected":
        let arguments = call.arguments as? [String: Any]
        if arguments?["connected"] as? Bool == true {
          keepAlive.start()
        } else {
          keepAlive.stop()
        }
        result(keepAlive.state.rawValue)
      case "keepAliveState":
        result(keepAlive.state.rawValue)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // Tell Dart when the system takes the session away or gives it back, so
    // the UI can warn that background output may stop.
    SilentAudioKeepAlive.shared.onStateChange = { [weak background] state in
      background?.invokeMethod("keepAliveStateChanged", arguments: state.rawValue)
    }
    backgroundChannel = background
  }

  private func navigationSide() -> String? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    switch scene?.interfaceOrientation {
    case .landscapeLeft:
      return "left"
    case .landscapeRight:
      return "right"
    default:
      return nil
    }
  }
}

/// Keeps the process running in the background with a silent, mixable audio
/// session while a Coyote is connected.
///
/// iOS can take the session away at any time: calls, Siri, alarms, other
/// apps, route changes and media-services resets. Apple does not guarantee
/// an "interruption ended" notification, so recovery does not depend on it.
/// Every signal that could mean the session is usable again triggers a
/// recovery attempt, and failed attempts retry with backoff until the
/// session is wanted no more.
final class SilentAudioKeepAlive: NSObject {
  static let shared = SilentAudioKeepAlive()

  enum State: String {
    /// Not requested.
    case idle
    /// Requested and the engine is producing (silent) output.
    case running
    /// Requested but the system has taken the session away. Background
    /// execution is not guaranteed until it recovers.
    case interrupted
  }

  /// Called on the main queue whenever [state] changes.
  var onStateChange: ((State) -> Void)?

  private(set) var state: State = .idle {
    didSet {
      guard state != oldValue else { return }
      // Keep the process alive briefly while the session is gone, so short
      // interruptions (Siri, a notification sound) never suspend the app
      // and the BLE sender keeps running.
      if state == .interrupted {
        beginGracePeriod()
      } else {
        endGracePeriod()
      }
      onStateChange?(state)
    }
  }

  /// Whether a connected Coyote currently wants the keep-alive.
  private var wanted = false
  private var graceTask: UIBackgroundTaskIdentifier = .invalid

  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var buffer: AVAudioPCMBuffer?
  private let format = AVAudioFormat(
    standardFormatWithSampleRate: 44_100,
    channels: 1
  )!
  private var retryWork: DispatchWorkItem?
  private var retryAttempt = 0
  private static let maxRetryDelay: TimeInterval = 30
  /// Backoff exponent to start from after an interruption begins (2^3 = 8s).
  private static let interruptedRetryStart = 3

  private override init() {
    super.init()
    let center = NotificationCenter.default
    let session = AVAudioSession.sharedInstance()
    center.addObserver(
      self, selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: session)
    center.addObserver(
      self, selector: #selector(handleMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification, object: session)
    center.addObserver(
      self, selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification, object: session)
    // Becoming active is the most reliable sign that a missed interruption
    // has ended, so re-check the session every time the app returns.
    center.addObserver(
      self, selector: #selector(handleDidBecomeActive(_:)),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  // MARK: Public control

  func start() {
    // A repeated request is a cheap health check.
    wanted = true
    recover()
  }

  func stop() {
    guard wanted else { return }
    wanted = false
    cancelRetry()
    state = .idle
    player?.stop()
    engine?.stop()
    do {
      // Let audio from other apps return to full volume or resume.
      try AVAudioSession.sharedInstance().setActive(
        false, options: [.notifyOthersOnDeactivation])
    } catch {
      NSLog("Background audio deactivation failed: \(error)")
    }
  }

  // MARK: Recovery

  /// Brings the session and engine to a playing state if they are wanted.
  /// Safe to call repeatedly from any recovery signal.
  private func recover() {
    guard wanted else { return }
    if state == .running && engine?.isRunning == true && player?.isPlaying == true { return }
    do {
      let session = AVAudioSession.sharedInstance()
      // Configure mixing before creating any audio graph or output node.
      if session.category != .playback || session.mode != .default
        || session.categoryOptions != [.mixWithOthers] {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      }
      try session.setActive(true)
      try prepareEngine()
      try play()
      cancelRetry()
      state = .running
    } catch {
      NSLog("Background audio recovery failed: \(error)")
      state = .interrupted
      scheduleRetry()
    }
  }

  private func play() throws {
    guard let engine, let player, let buffer else { throw KeepAliveError.bufferUnavailable }
    player.stop()
    if !engine.isRunning {
      engine.prepare()
      try engine.start()
    }
    player.scheduleBuffer(buffer, at: nil, options: .loops)
    player.play()
    guard engine.isRunning, player.isPlaying else {
      throw KeepAliveError.engineNotRunning
    }
  }

  private func scheduleRetry() {
    guard wanted, retryWork == nil else { return }
    // 1, 2, 4, 8, 16, 30, 30... seconds. Calls can last a long time, so
    // keep trying for as long as the keep-alive is wanted.
    let delay = min(pow(2, Double(retryAttempt)), Self.maxRetryDelay)
    retryAttempt += 1
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.retryWork = nil
      self.recover()
    }
    retryWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func cancelRetry() {
    retryWork?.cancel()
    retryWork = nil
    retryAttempt = 0
  }

  // MARK: System signals

  @objc private func handleInterruption(_ notification: Notification) {
    guard
      let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.wanted else { return }
      switch type {
      case .began:
        // The system already stopped the engine. Do not fight an active
        // call; wait for the end notification, a slow retry (in case the end
        // notification never arrives), or foregrounding.
        self.cancelRetry()
        self.retryAttempt = Self.interruptedRetryStart
        self.state = .interrupted
        self.scheduleRetry()
      case .ended:
        // The BLE connection still requests background execution; recovery
        // reasserts mixing before restarting the silent output.
        self.cancelRetry()
        self.recover()
      @unknown default:
        self.recover()
      }
    }
  }

  @objc private func handleMediaServicesReset(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      // All audio objects are invalid after a reset and must be rebuilt.
      self.rebuildEngine()
      guard self.wanted else { return }
      self.state = .interrupted
      self.cancelRetry()
      self.recover()
    }
  }

  @objc private func handleConfigurationChange(_ notification: Notification) {
    let changedEngine = notification.object as? AVAudioEngine
    DispatchQueue.main.async { [weak self] in
      guard let self, self.wanted, let changedEngine,
        changedEngine === self.engine else { return }
      // The engine stops itself on configuration changes.
      self.state = .interrupted
      self.recover()
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.wanted else { return }
      if self.engine?.isRunning != true || self.player?.isPlaying != true {
        self.state = .interrupted
        self.recover()
      }
    }
  }

  @objc private func handleDidBecomeActive(_ notification: Notification) {
    guard wanted else { return }
    cancelRetry()
    if state == .running && (engine?.isRunning != true || player?.isPlaying != true) {
      state = .interrupted
    }
    recover()
  }

  // MARK: Engine lifecycle

  private func prepareEngine() throws {
    guard engine == nil else { return }
    guard
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
      let channels = buffer.floatChannelData
    else { throw KeepAliveError.bufferUnavailable }
    buffer.frameLength = 44_100
    for channel in 0..<Int(format.channelCount) {
      memset(channels[channel], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    self.engine = engine
    self.player = player
    self.buffer = buffer
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleConfigurationChange(_:)),
      name: .AVAudioEngineConfigurationChange, object: engine)
  }

  private func rebuildEngine() {
    if let engine {
      NotificationCenter.default.removeObserver(
        self, name: .AVAudioEngineConfigurationChange, object: engine)
    }
    // Media-services resets invalidate the player as well as the engine.
    // Recreate both only after recover() configures the mixable session.
    player = nil
    engine = nil
    buffer = nil
  }

  private func beginGracePeriod() {
    guard graceTask == .invalid else { return }
    graceTask = UIApplication.shared.beginBackgroundTask(
      withName: "Coyote audio keep-alive recovery"
    ) { [weak self] in
      // Out of time. The app may now be suspended; recovery continues on
      // the next interruption end or foreground activation.
      self?.endGracePeriod()
    }
  }

  private func endGracePeriod() {
    guard graceTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(graceTask)
    graceTask = .invalid
  }

  private enum KeepAliveError: Error {
    case bufferUnavailable
    case engineNotRunning
  }
}
