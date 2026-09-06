import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class AuthenticatedAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
  let asset: AVURLAsset
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
      self, queue: DispatchQueue(label: "com.grape9113.Resume.asset-loader"))
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

    Task {
      do {
        let range: String?
        if let dataRequest = loadingRequest.dataRequest {
          let start = max(dataRequest.currentOffset, dataRequest.requestedOffset)
          range =
            dataRequest.requestsAllDataToEndOfResource
            ? "bytes=\(start)-"
            : "bytes=\(start)-\(start + Int64(dataRequest.requestedLength) - 1)"
        } else {
          range = nil
        }
        let response = try await fetch(url, range)
        if let info = loadingRequest.contentInformationRequest {
          info.contentLength =
            Self.totalLength(contentRange: response.contentRange) ?? response.expectedContentLength
          info.isByteRangeAccessSupported = response.statusCode == 206 || response.acceptsRanges
          if let mime = response.mimeType, let type = UTType(mimeType: mime) {
            info.contentType = type.identifier
          }
        }
        loadingRequest.dataRequest?.respond(with: response.data)
        loadingRequest.finishLoading()
      } catch {
        loadingRequest.finishLoading(with: error)
      }
    }
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {}

  private static func totalLength(contentRange: String?) -> Int64? {
    guard let total = contentRange?.split(separator: "/").last else { return nil }
    return Int64(total)
  }
}
