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

  init(
    onNetworkAvailable: @escaping @MainActor () -> Void,
    onOutputDeviceChanged: @escaping @MainActor () -> Void
  ) {
    pathMonitor.pathUpdateHandler = { path in
      guard path.status == .satisfied else { return }
      Task { @MainActor in onNetworkAvailable() }
    }
    pathMonitor.start(queue: queue)

    let listener: AudioObjectPropertyListenerBlock = { _, _ in
      Task { @MainActor in onOutputDeviceChanged() }
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
}
