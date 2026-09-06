import CoreAudio
import Foundation
import Network

final class SystemMonitor: @unchecked Sendable {
  private let pathMonitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.grape9113.Resume.system-monitor")
  private var outputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  private var outputListener: AudioObjectPropertyListenerBlock?
  private var currentOutputDevice: AudioDeviceID = kAudioObjectUnknown

  init(
    onNetworkAvailable: @escaping @MainActor () -> Void,
    onOutputDeviceRemoved: @escaping @MainActor () -> Void
  ) {
    pathMonitor.pathUpdateHandler = { path in
      guard path.status == .satisfied else { return }
      Task { @MainActor in onNetworkAvailable() }
    }
    pathMonitor.start(queue: queue)

    currentOutputDevice = Self.defaultOutputDevice()
    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self else { return }
      let previousDevice = self.currentOutputDevice
      self.currentOutputDevice = Self.defaultOutputDevice()
      guard previousDevice != kAudioObjectUnknown, !Self.isAlive(previousDevice) else { return }
      Task { @MainActor in onOutputDeviceRemoved() }
    }
    outputListener = listener
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &outputAddress, queue, listener)
  }

  deinit {
    pathMonitor.cancel()
    if let outputListener {
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &outputAddress, queue, outputListener)
    }
  }

  private static func defaultOutputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var device = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
    else { return kAudioObjectUnknown }
    return device
  }

  private static func isAlive(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsAlive,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var alive: UInt32 = 1
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr else {
      return false
    }
    return alive != 0
  }
}
