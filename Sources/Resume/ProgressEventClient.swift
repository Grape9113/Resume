import Foundation
import SocketIO

struct ExternalProgressEvent: Sendable {
  let itemID: String
  let sessionID: String?
  let progress: ABSProgress
}

private final class SocketReference: @unchecked Sendable {
  let socket: SocketIOClient

  init(_ socket: SocketIOClient) { self.socket = socket }
}

private func socketConnectHandler(
  socketReference: SocketReference,
  token: @escaping @Sendable () async -> String?
) -> NormalCallback {
  { _, _ in
    Task {
      guard let current = await token() else { return }
      await MainActor.run { socketReference.socket.emit("auth", current) }
    }
  }
}

private func socketProgressHandler(
  onProgress: @escaping @MainActor (ExternalProgressEvent) -> Void
) -> NormalCallback {
  { values, _ in
    guard let envelope = values.first as? [String: Any],
      let data = envelope["data"] as? [String: Any],
      let itemID = (data["libraryItemId"] ?? data["id"]) as? String,
      let currentTime = data["currentTime"] as? Double,
      let duration = data["duration"] as? Double,
      let lastUpdateNumber = data["lastUpdate"] as? NSNumber
    else { return }
    let progress = ABSProgress(
      currentTime: currentTime,
      duration: duration,
      isFinished: data["isFinished"] as? Bool ?? false,
      lastUpdate: lastUpdateNumber.int64Value
    )
    let event = ExternalProgressEvent(
      itemID: itemID, sessionID: envelope["sessionId"] as? String, progress: progress)
    Task { @MainActor in onProgress(event) }
  }
}

private func socketLibraryChangedHandler(
  onLibraryChanged: @escaping @MainActor () -> Void
) -> NormalCallback {
  { _, _ in Task { @MainActor in onLibraryChanged() } }
}

@MainActor
final class ProgressEventClient {
  private var manager: SocketManager?
  private var socket: SocketIOClient?

  func connect(
    server: URL,
    token: @escaping @Sendable () async -> String?,
    onProgress: @escaping @MainActor (ExternalProgressEvent) -> Void,
    onLibraryChanged: @escaping @MainActor () -> Void
  ) {
    disconnect()
    let manager = SocketManager(
      socketURL: server,
      config: [.compress, .reconnects(true), .forceWebsockets(true), .handleQueue(.main)])
    let socket = manager.defaultSocket
    socket.on(
      clientEvent: .connect,
      callback: socketConnectHandler(socketReference: SocketReference(socket), token: token))
    socket.on(
      "user_item_progress_updated", callback: socketProgressHandler(onProgress: onProgress))
    for event in ["item_added", "item_updated", "item_removed", "items_added", "items_updated"] {
      socket.on(event, callback: socketLibraryChangedHandler(onLibraryChanged: onLibraryChanged))
    }
    self.manager = manager
    self.socket = socket
    socket.connect()
  }

  func disconnect() {
    socket?.disconnect()
    socket = nil
    manager = nil
  }
}
