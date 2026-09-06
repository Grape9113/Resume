import AppKit
import Foundation

actor ArtworkStore {
  private let directory: URL

  init() {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    directory = caches.appending(path: "Resume/Artwork", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func image(itemID: String, revision: String?) -> NSImage? {
    let file = fileURL(itemID: itemID, revision: revision)
    if revision == nil,
      let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate,
      Date().timeIntervalSince(modified) > 24 * 60 * 60
    {
      try? FileManager.default.removeItem(at: file)
      return nil
    }
    return NSImage(contentsOf: file)
  }

  func save(_ data: Data, itemID: String, revision: String?) throws -> NSImage {
    let file = fileURL(itemID: itemID, revision: revision)
    try data.write(to: file, options: .atomic)
    guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
    return image
  }

  private func fileURL(itemID: String, revision: String?) -> URL {
    let safeRevision = (revision ?? "current").replacingOccurrences(of: "/", with: "-")
    return directory.appending(path: "\(itemID)-\(safeRevision).img")
  }

  func clear() { try? FileManager.default.removeItem(at: directory) }
}
