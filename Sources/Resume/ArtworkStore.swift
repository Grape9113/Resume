import AppKit
import Foundation
import ImageIO

actor ArtworkStore {
  private let directory: URL

  init(directory: URL? = nil) {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    self.directory =
      directory ?? caches.appending(path: "Resume/Artwork", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
  }

  func image(itemID: String, revision: String?) async -> NSImage? {
    let file = fileURL(itemID: itemID, revision: revision)
    if revision == nil,
      let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate,
      Date().timeIntervalSince(modified) > 24 * 60 * 60
    {
      try? FileManager.default.removeItem(at: file)
      return nil
    }
    guard let data = try? Data(contentsOf: file) else { return nil }
    return await Self.decode(data)
  }

  func save(_ data: Data, itemID: String, revision: String?) async throws -> NSImage {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = fileURL(itemID: itemID, revision: revision)
    try data.write(to: file, options: .atomic)
    guard let image = await Self.decode(data) else { throw CocoaError(.fileReadCorruptFile) }
    return image
  }

  private static func decode(_ data: Data) async -> NSImage? {
    // ImageIO decodes off the main actor without AppKit's shared format registry.
    // Bound cover memory to what the panel and system media controls can display.
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let pixels = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 1024,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { return nil }
    return await MainActor.run {
      NSImage(cgImage: pixels, size: .zero)
    }
  }

  private func fileURL(itemID: String, revision: String?) -> URL {
    let safeRevision = (revision ?? "current").replacingOccurrences(of: "/", with: "-")
    return directory.appending(path: "\(itemID)-\(safeRevision).img")
  }

  func clear() { try? FileManager.default.removeItem(at: directory) }
}
