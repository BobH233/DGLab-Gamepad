import AVFoundation
import Flutter
import MediaPlayer
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
      guard call.method == "setBleConnected" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      if arguments?["connected"] as? Bool == true {
        SilentAudioKeepAlive.shared.start()
      } else {
        SilentAudioKeepAlive.shared.stop()
      }
      result(nil)
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

private final class SilentAudioKeepAlive: NSObject {
  static let shared = SilentAudioKeepAlive()

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(
    standardFormatWithSampleRate: 44_100,
    channels: 1
  )!
  private var buffer: AVAudioPCMBuffer?
  private var active = false

  private override init() {
    super.init()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleConfigurationChange(_:)),
      name: .AVAudioEngineConfigurationChange,
      object: engine
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
  }

  func start() {
    guard !active else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      guard
        let silentBuffer = AVAudioPCMBuffer(
          pcmFormat: format,
          frameCapacity: 44_100
        ),
        let channels = silentBuffer.floatChannelData
      else {
        return
      }
      silentBuffer.frameLength = 44_100
      for channel in 0..<Int(format.channelCount) {
        memset(
          channels[channel],
          0,
          Int(silentBuffer.frameLength) * MemoryLayout<Float>.size
        )
      }
      buffer = silentBuffer
      active = true
      play()
      hideNowPlaying()
    } catch {
      NSLog("Background audio keep-alive failed: \(error)")
    }
  }

  func stop() {
    guard active else { return }
    active = false
    player.stop()
    engine.stop()
    buffer = nil
    do {
      // Let audio from other apps return to full volume / resume.
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
    } catch {
      NSLog("Background audio deactivation failed: \(error)")
    }
  }

  private func play() {
    guard let buffer else { return }
    do {
      player.stop()
      player.scheduleBuffer(buffer, at: nil, options: .loops)
      if !engine.isRunning {
        try engine.start()
      }
      player.play()
      hideNowPlaying()
    } catch {
      NSLog("Background audio restart failed: \(error)")
    }
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard
      let rawType = notification.userInfo?[
        AVAudioSessionInterruptionTypeKey
      ] as? UInt,
      AVAudioSession.InterruptionType(rawValue: rawType) == .ended
    else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      self?.restart()
    }
  }

  @objc private func handleConfigurationChange(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      self?.restart()
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    hideNowPlaying()
  }

  private func restart() {
    guard active else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      play()
      hideNowPlaying()
    } catch {
      NSLog("Background audio resumption failed: \(error)")
    }
  }

  private func hideNowPlaying() {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = false
    commands.pauseCommand.isEnabled = false
    commands.stopCommand.isEnabled = false
    commands.togglePlayPauseCommand.isEnabled = false
    commands.nextTrackCommand.isEnabled = false
    commands.previousTrackCommand.isEnabled = false
    commands.changePlaybackPositionCommand.isEnabled = false
    commands.skipForwardCommand.isEnabled = false
    commands.skipBackwardCommand.isEnabled = false
  }
}
