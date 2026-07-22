import AppKit
import Foundation
import UniformTypeIdentifiers

struct SkinStatus: Decodable {
  var session = "off"
  var port = 9341
  var injectorAlive = false
  var cdpOk = false
  var codexRunning = false
  var themeName = ""

  var isActive: Bool { session == "active" && injectorAlive }
  var isPaused: Bool { session == "paused" }
}

struct SavedTheme: Identifiable, Hashable {
  let id: String
  let name: String
  let imageURL: URL?
  let sourceURL: URL?
  let sourceAuthor: String?
  let sourceLicense: String?
}

struct CommandResult {
  let output: String
  let succeeded: Bool
}

struct OnlineDownloadStatus {
  var progress: Double
  var isPaused = false
  var isProcessing = false
}

@MainActor
final class DreamSkinModel: ObservableObject {
  @Published var status = SkinStatus()
  @Published var themes: [SavedTheme] = []
  @Published var selectedThemeID: String?
  @Published var isWorking = false
  @Published var activity = L10n.text("Ready")
  @Published var lastOutput = ""
  @Published var alertMessage: String?
  @Published var onlineWallpapers: [OnlineWallpaper] = []
  @Published var communityWallpapers: [OnlineWallpaper] = []
  @Published var isSearchingOnline = false
  @Published var onlineMessage = L10n.text("Search nature, cities, space, or any style you like.")
  @Published var onlineDownloads: [Int: OnlineDownloadStatus] = [:]

  private let fileManager = FileManager.default
  private var activeDownloads: [Int: OnlineWallpaperService.Download] = [:]

  var installedEngineURL: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/codex-dream-skin-studio", isDirectory: true)
  }

  var stateRootURL: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/CodexDreamSkinStudio", isDirectory: true)
  }

  var isInstalled: Bool {
    fileManager.isExecutableFile(atPath: scriptURL("start-dream-skin-macos.sh").path)
  }

  var installedVersion: String? {
    version(at: installedEngineURL)
  }

  var bundledVersion: String? {
    bundledEngineURL.flatMap(version(at:))
  }

  var engineNeedsUpdate: Bool {
    guard let installedVersion, let bundledVersion else { return false }
    return installedVersion != bundledVersion
      || !engineSupportsOnlineAttribution
      || !engineSupportsCommunitySource
      || !engineSupportsExactCodexDetection
  }

  var engineSummary: String {
    guard isInstalled else { return L10n.text("Install the local engine first") }
    if engineNeedsUpdate {
      if installedVersion == bundledVersion {
        return L10n.text("Engine update required")
      }
      return L10n.format(
        "Engine %@, update available: %@",
        installedVersion ?? L10n.text("Unknown"),
        bundledVersion ?? L10n.text("Current version")
      )
    }
    return installedVersion.map { L10n.format("Engine %@ installed", $0) }
      ?? L10n.text("Engine installed")
  }

  private var bundledEngineURL: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("Engine", isDirectory: true)
  }

  private var engineSupportsOnlineAttribution: Bool {
    let url = scriptURL("load-image-theme-macos.sh")
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
    return source.contains("--source-url)") && source.contains("--source-provider)")
  }

  private var engineSupportsCommunitySource: Bool {
    let url = scriptURL("write-theme.mjs")
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
    return source.contains("/iStig/Codex-Skin-Clinet/issues/")
  }

  private var engineSupportsExactCodexDetection: Bool {
    let url = scriptURL("status-dream-skin-macos.sh")
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
    return source.contains("CFBundleIdentifier") && !source.contains("pgrep -x ChatGPT")
  }

  init() {
    Task { await refresh() }
  }

  func refresh() async {
    loadThemes()
    guard isInstalled else {
      status = SkinStatus()
      activity = L10n.text("Skin engine needs to be installed")
      return
    }
    guard let decoded = await engineStatus(at: installedEngineURL) else {
      activity = L10n.text("Unable to read engine status")
      return
    }
    status = decoded
    activity = decoded.isActive
      ? L10n.text("Skin is running")
      : decoded.isPaused ? L10n.text("Skin is paused") : L10n.text("Skin is off")
  }

  func install() async {
    guard let bundledEngineURL else {
      alertMessage = L10n.text("Installation resources are missing from the app. Rebuild or download it again.")
      return
    }
    guard let currentStatus = await engineStatus(at: bundledEngineURL) else {
      alertMessage = L10n.text("Unable to read engine status")
      return
    }
    status = currentStatus
    guard !currentStatus.codexRunning else {
      alertMessage = L10n.text("Close Codex before installing or updating the engine.")
      return
    }
    await perform(L10n.text("Installing engine…")) {
      await self.run(
        bundledEngineURL.appendingPathComponent("scripts/install-dream-skin-macos.sh"),
        ["--no-launchers", "--no-launch"]
      )
    }
  }

  func apply() async {
    await perform(L10n.text("Starting Codex and applying skin…")) {
      await self.run(self.scriptURL("start-dream-skin-macos.sh"), ["--prompt-restart"])
    }
  }

  func pause() async {
    await perform(L10n.text("Stopping skin…")) {
      await self.run(self.scriptURL("pause-dream-skin-macos.sh"), [])
    }
  }

  func restore() async {
    await perform(L10n.text("Restoring official appearance…")) {
      await self.run(
        self.scriptURL("restore-dream-skin-macos.sh"),
        ["--restore-base-theme", "--restart-codex"]
      )
    }
  }

  func switchTheme(_ theme: SavedTheme) async {
    selectedThemeID = theme.id
    await perform(L10n.format("Switching to %@…", theme.name)) {
      await self.run(self.scriptURL("switch-theme-macos.sh"), ["--id", theme.id])
    }
  }

  func deleteTheme(_ theme: SavedTheme) {
    guard theme.name != status.themeName else {
      alertMessage = L10n.text("Switch to another theme before deleting the current theme.")
      return
    }
    let themesRoot = stateRootURL.appendingPathComponent("themes", isDirectory: true).standardizedFileURL
    let target = themesRoot.appendingPathComponent(theme.id, isDirectory: true).standardizedFileURL
    guard target.path.hasPrefix(themesRoot.path + "/") else { return }
    do {
      try fileManager.removeItem(at: target)
      loadThemes()
      lastOutput = L10n.format("Deleted theme %@", theme.name)
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  func importImage() async {
    let panel = NSOpenPanel()
    panel.title = L10n.text("Choose a background image")
    panel.prompt = L10n.text("Import and Apply")
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let name = url.deletingPathExtension().lastPathComponent
    await perform(L10n.text("Processing background image…")) {
      await self.run(
        self.scriptURL("load-image-theme-macos.sh"),
        ["--file", url.path, "--name", name]
      )
    }
  }

  func searchOnlineWallpapers(_ query: String) async {
    guard !isSearchingOnline else { return }
    isSearchingOnline = true
    onlineMessage = L10n.text("Searching Wikimedia Commons…")
    do {
      onlineWallpapers = try await OnlineWallpaperService.search(query)
      onlineMessage = L10n.format("Found %d high-resolution landscape images", onlineWallpapers.count)
    } catch {
      onlineWallpapers = []
      onlineMessage = error.localizedDescription
    }
    isSearchingOnline = false
  }

  func loadCommunityWallpapers() async {
    guard !isSearchingOnline else { return }
    isSearchingOnline = true
    onlineMessage = L10n.text("Loading community wallpapers…")
    do {
      communityWallpapers = try await OnlineWallpaperService.community()
      onlineMessage = L10n.format("Found %d community wallpapers", communityWallpapers.count)
    } catch {
      communityWallpapers = []
      onlineMessage = error.localizedDescription
    }
    isSearchingOnline = false
  }

  func openCommunitySubmission() {
    guard let url = URL(string: "https://github.com/iStig/Codex-Skin-Clinet/issues/new?template=community_wallpaper.yml") else { return }
    NSWorkspace.shared.open(url)
  }

  func downloadedTheme(for wallpaper: OnlineWallpaper) -> SavedTheme? {
    themes.first { $0.id == "online-\(wallpaper.id)" || $0.sourceURL == wallpaper.detailsURL }
  }

  func downloadOnlineWallpaper(_ wallpaper: OnlineWallpaper) {
    guard isInstalled else {
      alertMessage = L10n.text("Install the skin engine first.")
      return
    }
    guard !engineNeedsUpdate else {
      alertMessage = L10n.text("Update the engine before applying online wallpapers.")
      return
    }
    guard downloadedTheme(for: wallpaper) == nil, activeDownloads[wallpaper.id] == nil else { return }

    let download = OnlineWallpaperService.download(wallpaper) { progress in
      Task { @MainActor in
        guard var status = self.onlineDownloads[wallpaper.id] else { return }
        status.progress = progress
        self.onlineDownloads[wallpaper.id] = status
      }
    }
    activeDownloads[wallpaper.id] = download
    onlineDownloads[wallpaper.id] = OnlineDownloadStatus(progress: 0)
    Task { await finishOnlineDownload(wallpaper, download: download) }
  }

  private func finishOnlineDownload(
    _ wallpaper: OnlineWallpaper,
    download: OnlineWallpaperService.Download
  ) async {
    var downloadedFile: URL?
    defer {
      if let downloadedFile { try? fileManager.removeItem(at: downloadedFile) }
      activeDownloads[wallpaper.id] = nil
      onlineDownloads[wallpaper.id] = nil
    }
    do {
      let file = try await download.start()
      downloadedFile = file
      onlineDownloads[wallpaper.id] = OnlineDownloadStatus(progress: 1, isProcessing: true)
      let result = await run(
        scriptURL("load-image-theme-macos.sh"),
        [
          "--file", file.path,
          "--name", wallpaper.title,
          "--source-url", wallpaper.detailsURL.absoluteString,
          "--source-author", wallpaper.artist,
          "--source-license", wallpaper.license,
          "--source-provider", wallpaper.provider,
          "--save-only",
          "--theme-id", "online-\(wallpaper.id)"
        ]
      )
      if result.succeeded {
        loadThemes()
        onlineMessage = L10n.format("Downloaded %@", wallpaper.title)
      } else {
        alertMessage = result.output
      }
    } catch {
      if (error as? URLError)?.code != .cancelled {
        alertMessage = error.localizedDescription
      }
    }
  }

  func applyOnlineWallpaper(_ wallpaper: OnlineWallpaper) async {
    guard let theme = downloadedTheme(for: wallpaper) else {
      downloadOnlineWallpaper(wallpaper)
      return
    }
    await switchTheme(theme)
  }

  func pauseOnlineDownload(_ id: Int) {
    activeDownloads[id]?.pause()
    if var status = onlineDownloads[id] {
      status.isPaused = true
      onlineDownloads[id] = status
    }
  }

  func resumeOnlineDownload(_ id: Int) {
    activeDownloads[id]?.resume()
    if var status = onlineDownloads[id] {
      status.isPaused = false
      onlineDownloads[id] = status
    }
  }

  func cancelOnlineDownload(_ id: Int) {
    activeDownloads[id]?.cancel()
  }

  func openThemeFolder() {
    let url = stateRootURL.appendingPathComponent("themes", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.open(url)
  }

  private func perform(_ message: String, operation: @escaping () async -> CommandResult) async {
    guard !isWorking else { return }
    isWorking = true
    activity = message
    let result = await operation()
    lastOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    isWorking = false
    if !result.succeeded {
      alertMessage = lastOutput.isEmpty
        ? L10n.text("The operation failed. Check that Codex is installed and closed when required.")
        : lastOutput
    }
    await refresh()
  }

  private func scriptURL(_ name: String) -> URL {
    installedEngineURL.appendingPathComponent("scripts/\(name)")
  }

  private func engineStatus(at engineURL: URL) async -> SkinStatus? {
    let statusScript = engineURL.appendingPathComponent("scripts/status-dream-skin-macos.sh")
    let result = await run(statusScript, ["--json", "--deep"])
    guard result.succeeded, let data = result.output.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SkinStatus.self, from: data)
  }

  private func version(at engineURL: URL) -> String? {
    let url = engineURL.appendingPathComponent("VERSION")
    guard let value = try? String(contentsOf: url, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty else { return nil }
    return value
  }

  private func loadThemes() {
    let root = stateRootURL.appendingPathComponent("themes", isDirectory: true)
    let rootPath = root.standardizedFileURL.path + "/"
    let directories = (try? fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    themes = directories.compactMap { directory in
      guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
      let id = directory.lastPathComponent
      guard id.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil,
            directory.standardizedFileURL.path.hasPrefix(rootPath) else { return nil }
      let themeURL = directory.appendingPathComponent("theme.json")
      guard let data = try? Data(contentsOf: themeURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
      let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let imageName = json["image"] as? String,
            URL(fileURLWithPath: imageName).lastPathComponent == imageName else { return nil }
      let imageURL = directory.appendingPathComponent(imageName).standardizedFileURL
      guard imageURL.path.hasPrefix(directory.standardizedFileURL.path + "/"),
            fileManager.isReadableFile(atPath: imageURL.path) else { return nil }
      let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? id
      let source = json["source"] as? [String: Any]
      let sourceURL = trustedSourceURL(source?["url"] as? String)
      let sourceAuthor = source?["author"] as? String
      let sourceLicense = source?["license"] as? String
      return SavedTheme(
        id: id,
        name: displayName,
        imageURL: imageURL,
        sourceURL: sourceURL,
        sourceAuthor: sourceAuthor,
        sourceLicense: sourceLicense
      )
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private func trustedSourceURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), url.scheme == "https" else { return nil }
    let wikimedia = url.host?.lowercased() == "commons.wikimedia.org"
    let community = url.host?.lowercased() == "github.com" &&
      url.path.hasPrefix("/iStig/Codex-Skin-Clinet/issues/")
    guard wikimedia || community else { return nil }
    return url
  }

  private nonisolated func run(_ executable: URL, _ arguments: [String]) async -> CommandResult {
    await Task.detached(priority: .userInitiated) {
      let process = Process()
      let pipe = Pipe()
      process.executableURL = executable
      process.arguments = arguments
      process.standardOutput = pipe
      process.standardError = pipe
      process.environment = ProcessInfo.processInfo.environment.merging([
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
      ]) { _, new in new }
      do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
          output: String(decoding: data, as: UTF8.self),
          succeeded: process.terminationStatus == 0
        )
      } catch {
        return CommandResult(output: error.localizedDescription, succeeded: false)
      }
    }.value
  }
}
