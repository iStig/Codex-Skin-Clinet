import AppKit
import SwiftUI

private final class RemoteImageCache {
  static let shared = RemoteImageCache()
  let images = NSCache<NSURL, NSImage>()

  private init() {
    images.countLimit = 160
    images.totalCostLimit = 128 * 1024 * 1024
  }
}

@MainActor
private final class RemoteImageLoader: ObservableObject {
  @Published var image: NSImage?
  @Published var failed = false
  private let url: URL

  init(url: URL) {
    self.url = url
    image = RemoteImageCache.shared.images.object(forKey: url as NSURL)
  }

  func load() async {
    guard image == nil, !failed else { return }
    if let cached = RemoteImageCache.shared.images.object(forKey: url as NSURL) {
      image = cached
      return
    }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let image = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
      RemoteImageCache.shared.images.setObject(image, forKey: url as NSURL, cost: data.count)
      self.image = image
    } catch {
      failed = true
    }
  }
}

struct CachedRemoteImage: View {
  @StateObject private var loader: RemoteImageLoader

  init(url: URL) {
    _loader = StateObject(wrappedValue: RemoteImageLoader(url: url))
  }

  var body: some View {
    Group {
      if let image = loader.image {
        Image(nsImage: image).resizable().scaledToFill()
      } else if loader.failed {
        Image(systemName: "photo.badge.exclamationmark")
          .font(.title)
          .foregroundStyle(.secondary)
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task { await loader.load() }
  }
}
