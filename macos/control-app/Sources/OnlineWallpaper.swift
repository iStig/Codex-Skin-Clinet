import Foundation

struct OnlineWallpaper: Identifiable, Hashable {
  let id: Int
  let title: String
  let originalURL: URL
  let thumbnailURL: URL
  let detailsURL: URL
  let width: Int
  let height: Int
  let byteCount: Int
  let artist: String
  let license: String
  let provider: String
  let fileExtension: String

  var resolution: String { "\(width) × \(height)" }
}

enum OnlineWallpaperError: LocalizedError {
  case invalidQuery
  case invalidResponse
  case requestFailed(Int)
  case noSuitableImages
  case unsafeDownload
  case imageTooLarge

  var errorDescription: String? {
    switch self {
    case .invalidQuery: return L10n.text("Enter a scene or style to search for.")
    case .invalidResponse: return L10n.text("The online gallery returned unrecognized data.")
    case .requestFailed(let code): return L10n.format("Online gallery request failed (HTTP %d).", code)
    case .noSuitableImages: return L10n.text("No suitable high-resolution landscape images were found. Try another query.")
    case .unsafeDownload: return L10n.text("The gallery returned an untrusted image address.")
    case .imageTooLarge: return L10n.text("The original image exceeds 50 MB and cannot be imported.")
    }
  }
}

enum OnlineWallpaperService {
  private static let maximumBytes = 50 * 1024 * 1024

  final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let wallpaper: OnlineWallpaper
    private let onProgress: @Sendable (Double) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadedURL: URL?
    private var downloadError: Error?

    init(wallpaper: OnlineWallpaper, onProgress: @escaping @Sendable (Double) -> Void) {
      self.wallpaper = wallpaper
      self.onProgress = onProgress
    }

    func start() async throws -> URL {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: wallpaper.originalURL, timeoutInterval: 60)
        request.setValue("CodexDreamSkin/1.4 (macOS wallpaper browser)", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        self.task = task
        task.resume()
      }
    }

    func pause() { task?.suspend() }
    func resume() { task?.resume() }
    func cancel() { task?.cancel() }

    func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      guard totalBytesExpectedToWrite > 0 else { return }
      onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      do {
        downloadedURL = try OnlineWallpaperService.validateAndMove(
          location,
          response: downloadTask.response,
          wallpaper: wallpaper
        )
      } catch {
        downloadError = error
      }
    }

    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didCompleteWithError error: Error?
    ) {
      let continuation = continuation
      self.continuation = nil
      self.task = nil
      self.session?.finishTasksAndInvalidate()
      self.session = nil
      if let error { continuation?.resume(throwing: error) }
      else if let downloadError { continuation?.resume(throwing: downloadError) }
      else if let downloadedURL { continuation?.resume(returning: downloadedURL) }
      else { continuation?.resume(throwing: OnlineWallpaperError.invalidResponse) }
    }
  }

  static func search(_ rawQuery: String) async throws -> [OnlineWallpaper] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, query.count <= 120 else { throw OnlineWallpaperError.invalidQuery }

    var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
    components?.queryItems = [
      URLQueryItem(name: "action", value: "query"),
      URLQueryItem(name: "generator", value: "search"),
      URLQueryItem(name: "gsrsearch", value: "\(query) landscape filetype:bitmap"),
      URLQueryItem(name: "gsrnamespace", value: "6"),
      URLQueryItem(name: "gsrlimit", value: "40"),
      URLQueryItem(name: "prop", value: "imageinfo"),
      URLQueryItem(name: "iiprop", value: "url|size|extmetadata"),
      URLQueryItem(name: "iiurlwidth", value: "720"),
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "formatversion", value: "2"),
      URLQueryItem(name: "origin", value: "*")
    ]
    guard let url = components?.url else { throw OnlineWallpaperError.invalidQuery }

    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue("CodexDreamSkin/1.4 (macOS wallpaper browser)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw OnlineWallpaperError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw OnlineWallpaperError.requestFailed(http.statusCode) }
    let results = try parseSearchResponse(data)
    guard !results.isEmpty else { throw OnlineWallpaperError.noSuitableImages }
    return results
  }

  static func community() async throws -> [OnlineWallpaper] {
    let url = URL(string: "https://raw.githubusercontent.com/iStig/Codex-Skin-Clinet/main/community/catalog.json")!
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("CodexDreamSkin/1.4 (macOS community gallery)", forHTTPHeaderField: "User-Agent")
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw OnlineWallpaperError.invalidResponse }
      guard (200..<300).contains(http.statusCode) else { throw OnlineWallpaperError.requestFailed(http.statusCode) }
      return try parseCommunityResponse(data)
    } catch {
      guard let fallback = Bundle.main.resourceURL?
        .appendingPathComponent("Engine/community/catalog.json"),
        let data = try? Data(contentsOf: fallback) else { throw error }
      return try parseCommunityResponse(data)
    }
  }

  static func parseCommunityResponse(_ data: Data) throws -> [OnlineWallpaper] {
    let catalog: CommunityCatalog
    do { catalog = try JSONDecoder().decode(CommunityCatalog.self, from: data) }
    catch { throw OnlineWallpaperError.invalidResponse }
    guard catalog.schemaVersion == 1 else { throw OnlineWallpaperError.invalidResponse }
    return catalog.items.compactMap { item in
      guard item.id >= 1_000_000,
            item.title.count <= 160,
            item.artist.count <= 160,
            item.license.count <= 120,
            item.width >= 1920,
            item.height >= 900,
            item.byteCount > 0,
            item.byteCount <= maximumBytes,
            Double(item.width) / Double(item.height) >= 1.45,
            Double(item.width) / Double(item.height) <= 2.6,
            let originalURL = trustedCommunityImageURL(item.originalURL, allowRedirectHost: false),
            let thumbnailURL = trustedCommunityImageURL(item.thumbnailURL, allowRedirectHost: false),
            let detailsURL = trustedCommunityDetailsURL(item.detailsURL),
            let extensionName = safeExtension(item.fileExtension) else { return nil }
      return OnlineWallpaper(
        id: item.id,
        title: item.title,
        originalURL: originalURL,
        thumbnailURL: thumbnailURL,
        detailsURL: detailsURL,
        width: item.width,
        height: item.height,
        byteCount: item.byteCount,
        artist: item.artist,
        license: item.license,
        provider: "Dream Skin Community",
        fileExtension: extensionName
      )
    }
  }

  static func parseSearchResponse(_ data: Data) throws -> [OnlineWallpaper] {
    let response: CommonsResponse
    do {
      response = try JSONDecoder().decode(CommonsResponse.self, from: data)
    } catch {
      throw OnlineWallpaperError.invalidResponse
    }
    let pages = response.query?.pages ?? []
    return pages.compactMap { page in
      guard let pageID = page.pageid,
            let pageTitle = page.title,
            let info = page.imageinfo?.first,
            let width = info.width,
            let height = info.height,
            let size = info.size,
            width >= 1920,
            height >= 900,
            size > 0,
            size <= maximumBytes else { return nil }
      let ratio = Double(width) / Double(height)
      guard ratio >= 1.45, ratio <= 2.6,
            let originalURL = trustedImageURL(info.url),
            safeExtension(originalURL.pathExtension) != nil,
            let thumbnailURL = trustedImageURL(info.thumburl),
            let detailsURL = trustedDetailsURL(info.descriptionurl) else { return nil }

      let metadata = info.extmetadata
      let artist = cleanMetadata(metadata?["Artist"]?.value) ?? "Wikimedia Commons contributor"
      let license = cleanMetadata(metadata?["LicenseShortName"]?.value)
        ?? cleanMetadata(metadata?["UsageTerms"]?.value)
        ?? "See source license"
      let title = pageTitle
        .replacingOccurrences(of: "File:", with: "")
        .replacingOccurrences(of: "_", with: " ")
      return OnlineWallpaper(
        id: pageID,
        title: title,
        originalURL: originalURL,
        thumbnailURL: thumbnailURL,
        detailsURL: detailsURL,
        width: width,
        height: height,
        byteCount: size,
        artist: artist,
        license: license,
        provider: "Wikimedia Commons",
        fileExtension: originalURL.pathExtension.lowercased()
      )
    }
    .sorted {
      let left = $0.width * $0.height
      let right = $1.width * $1.height
      return left == right ? $0.id < $1.id : left > right
    }
  }

  static func download(
    _ wallpaper: OnlineWallpaper,
    onProgress: @escaping @Sendable (Double) -> Void
  ) -> Download {
    Download(wallpaper: wallpaper, onProgress: onProgress)
  }

  private static func validateAndMove(
    _ temporaryURL: URL,
    response: URLResponse?,
    wallpaper: OnlineWallpaper
  ) throws -> URL {
    let trustedOriginal = wallpaper.provider == "Dream Skin Community"
      ? trustedCommunityImageURL(wallpaper.originalURL.absoluteString, allowRedirectHost: false)
      : trustedImageURL(wallpaper.originalURL.absoluteString)
    guard trustedOriginal != nil else {
      throw OnlineWallpaperError.unsafeDownload
    }
    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode),
          (wallpaper.provider == "Dream Skin Community"
            ? trustedCommunityImageURL(http.url?.absoluteString, allowRedirectHost: true)
            : trustedImageURL(http.url?.absoluteString)) != nil else {
      throw OnlineWallpaperError.invalidResponse
    }
    if http.expectedContentLength > Int64(maximumBytes) { throw OnlineWallpaperError.imageTooLarge }
    let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
      throw OnlineWallpaperError.invalidResponse
    }
    guard size <= maximumBytes else { throw OnlineWallpaperError.imageTooLarge }

    guard let extensionName = safeExtension(wallpaper.fileExtension) else {
      throw OnlineWallpaperError.unsafeDownload
    }
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexDreamSkinDownloads", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let destination = root.appendingPathComponent("\(UUID().uuidString).\(extensionName)")
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
    return destination
  }

  private static func trustedImageURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), url.scheme == "https",
          let host = url.host?.lowercased(),
          host == "upload.wikimedia.org" || host.hasSuffix(".wikimedia.org") else { return nil }
    return url
  }

  private static func trustedDetailsURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), url.scheme == "https",
          let host = url.host?.lowercased(),
          host == "commons.wikimedia.org" else { return nil }
    return url
  }

  private static func trustedCommunityDetailsURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), url.scheme == "https",
          url.host?.lowercased() == "github.com",
          url.path.hasPrefix("/iStig/Codex-Skin-Clinet/issues/") else { return nil }
    return url
  }

  private static func trustedCommunityImageURL(_ value: String?, allowRedirectHost: Bool) -> URL? {
    guard let value, let url = URL(string: value), url.scheme == "https",
          let host = url.host?.lowercased() else { return nil }
    if host == "github.com" && url.path.hasPrefix("/user-attachments/assets/") { return url }
    if host == "raw.githubusercontent.com" && url.path.hasPrefix("/iStig/Codex-Skin-Clinet/") { return url }
    if allowRedirectHost && host == "objects.githubusercontent.com" { return url }
    return nil
  }

  private static func safeExtension(_ value: String) -> String? {
    let normalized = value.lowercased()
    return ["jpg", "jpeg", "png", "webp", "tif", "tiff"].contains(normalized) ? normalized : nil
  }

  private static func cleanMetadata(_ value: String?) -> String? {
    guard var value, !value.isEmpty else { return nil }
    value = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
    for (entity, replacement) in entities { value = value.replacingOccurrences(of: entity, with: replacement) }
    value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : String(value.prefix(160))
  }
}

private struct CommunityCatalog: Decodable {
  let schemaVersion: Int
  let items: [CommunityItem]
}

private struct CommunityItem: Decodable {
  let id: Int
  let title: String
  let originalURL: String
  let thumbnailURL: String
  let detailsURL: String
  let width: Int
  let height: Int
  let byteCount: Int
  let artist: String
  let license: String
  let fileExtension: String
}

private struct CommonsResponse: Decodable {
  let query: CommonsQuery?
}

private struct CommonsQuery: Decodable {
  let pages: [CommonsPage]?

  private enum CodingKeys: String, CodingKey { case pages }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let array = try? container.decode([CommonsPage].self, forKey: .pages) {
      pages = array
    } else if let dictionary = try? container.decode([String: CommonsPage].self, forKey: .pages) {
      pages = Array(dictionary.values)
    } else {
      pages = nil
    }
  }
}

private struct CommonsPage: Decodable {
  let pageid: Int?
  let title: String?
  let imageinfo: [CommonsImageInfo]?
}

private struct CommonsImageInfo: Decodable {
  let size: Int?
  let width: Int?
  let height: Int?
  let url: String?
  let descriptionurl: String?
  let thumburl: String?
  let extmetadata: [String: CommonsMetadata]?
}

private struct CommonsMetadata: Decodable {
  let value: String?

  private enum CodingKeys: String, CodingKey { case value }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let string = try? container.decode(String.self, forKey: .value) {
      value = string
    } else if let integer = try? container.decode(Int.self, forKey: .value) {
      value = String(integer)
    } else if let number = try? container.decode(Double.self, forKey: .value) {
      value = String(number)
    } else {
      value = nil
    }
  }
}
