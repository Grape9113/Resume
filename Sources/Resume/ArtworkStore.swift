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
        NSImage(contentsOf: fileURL(itemID: itemID, revision: revision))
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
