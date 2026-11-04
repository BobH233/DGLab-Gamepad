import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    SilentAudioKeepAlive.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    } catch {
      NSLog("Background audio keep-alive failed: \(error)")
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

  private func restart() {
    guard active else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      play()
    } catch {
      NSLog("Background audio resumption failed: \(error)")
    }
  }
}
