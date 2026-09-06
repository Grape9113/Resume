import Foundation
import SocketIO

struct ExternalProgressEvent: Sendable {
  let itemID: String
  let sessionID: String?
  let progress: ABSProgress
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
      socketURL: server, config: [.compress, .reconnects(true), .forceWebsockets(true)])
    let socket = manager.defaultSocket
    socket.on(clientEvent: .connect) { _, _ in
      Task {
        guard let current = await token() else { return }
        socket.emit("auth", current)
      }
    }
    socket.on("user_item_progress_updated") { values, _ in
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
    for event in ["item_added", "item_updated", "item_removed", "items_added", "items_updated"] {
      socket.on(event) { _, _ in Task { @MainActor in onLibraryChanged() } }
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
