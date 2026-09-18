import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class AuthenticatedAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
  let asset: AVURLAsset
  private let queue = DispatchQueue(label: "com.grape9113.Resume.asset-loader")
  // Accessed only on the resource-loader queue.
  private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
  private var isCancelled = false
  private let sourceScheme: String
  private let fetch: @Sendable (URL, String?) async throws -> AuthenticatedMediaResponse

  init(
    url: URL, fetch: @escaping @Sendable (URL, String?) async throws -> AuthenticatedMediaResponse
  ) throws {
    guard let scheme = url.scheme,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw URLError(.badURL) }
    sourceScheme = scheme
    components.scheme = "resume-\(scheme)"
    guard let protectedURL = components.url else { throw URLError(.badURL) }
    self.fetch = fetch
    asset = AVURLAsset(url: protectedURL)
    super.init()
    asset.resourceLoader.setDelegate(
      self, queue: queue)
  }

  func cancel() {
    asset.cancelLoading()
    queue.async { [self] in
      isCancelled = true
      for task in requests.values { task.cancel() }
      requests.removeAll()
    }
  }

  deinit {
    for task in requests.values { task.cancel() }
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let protectedURL = loadingRequest.request.url,
      var components = URLComponents(url: protectedURL, resolvingAgainstBaseURL: false)
    else { return false }
    components.scheme = sourceScheme
    guard let url = components.url else { return false }

    loadNextChunk(url: url, request: loadingRequest)
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    requests.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
  }

  private func loadNextChunk(url: URL, request: AVAssetResourceLoadingRequest) {
    guard !request.isCancelled, !request.isFinished else { return }
    guard !isCancelled else {
      request.finishLoading(with: CancellationError())
      return
    }
    let key = ObjectIdentifier(request)
    let dataRequest = request.dataRequest
    let start = dataRequest.map { max($0.currentOffset, $0.requestedOffset) } ?? 0
    let requestedEnd = dataRequest.flatMap {
      $0.requestsAllDataToEndOfResource ? nil : $0.requestedOffset + Int64($0.requestedLength)
    }
    // URLSession.data(for:) buffers its response. Never give it an open-ended book range.
    let end = min(start + 256 * 1024, requestedEnd ?? Int64.max)
    guard end > start else {
      requests.removeValue(forKey: key)
      request.finishLoading()
      return
    }
    requests[key] = Task { [fetch, weak self] in
      do {
        let response = try await fetch(url, "bytes=\(start)-\(end - 1)")
        try Task.checkCancellation()
        self?.queue.async { [weak self] in
          guard let self, !request.isCancelled, !request.isFinished else { return }
          self.requests.removeValue(forKey: key)
          let total =
            Self.totalLength(contentRange: response.contentRange)
            ?? response.expectedContentLength
          if let info = request.contentInformationRequest {
            info.contentLength = total
            info.isByteRangeAccessSupported = response.statusCode == 206 || response.acceptsRanges
            if let mime = response.mimeType, let type = UTType(mimeType: mime) {
              info.contentType = type.identifier
            }
          }
          // A server that ignores Range returns the resource starting at zero.
          let offset = response.statusCode == 206 ? 0 : Int(start)
          let count = min(Int(end - start), response.data.count - offset)
          guard count > 0 else {
            request.finishLoading(with: URLError(.badServerResponse))
            return
          }
          dataRequest?.respond(with: response.data.subdata(in: offset..<(offset + count)))
          let next = start + Int64(count)
          if dataRequest == nil || next >= total || next >= (requestedEnd ?? Int64.max) {
            request.finishLoading()
          } else {
            self.loadNextChunk(url: url, request: request)
          }
        }
      } catch {
        self?.queue.async { [weak self] in
          self?.requests.removeValue(forKey: key)
          if !request.isCancelled, !request.isFinished { request.finishLoading(with: error) }
        }
      }
    }
  }

  private static func totalLength(contentRange: String?) -> Int64? {
    guard let total = contentRange?.split(separator: "/").last else { return nil }
    return Int64(total)
  }
}
