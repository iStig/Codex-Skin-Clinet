import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: DreamSkinModel
  @State private var showRestoreConfirmation = false
  @State private var themeToDelete: SavedTheme?
  @State private var selectedSection = LibrarySection.local
  @State private var onlineQuery = "cinematic landscape"
  @State private var onlineSource = OnlineGallerySource.wikimedia

  private var statusColor: Color {
    if model.status.isActive { return .green }
    if model.status.isPaused { return .orange }
    return .secondary
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      mainContent
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .alert(L10n.text("Operation Not Completed"), isPresented: Binding(
      get: { model.alertMessage != nil },
      set: { if !$0 { model.alertMessage = nil } }
    )) {
      Button(L10n.text("OK"), role: .cancel) { model.alertMessage = nil }
    } message: {
      Text(model.alertMessage ?? "")
    }
    .confirmationDialog(
      L10n.text("This closes the debug session and restarts Codex with its official appearance."),
      isPresented: $showRestoreConfirmation,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Restore Official Appearance"), role: .destructive) { Task { await model.restore() } }
      Button(L10n.text("Cancel"), role: .cancel) { }
    }
    .confirmationDialog(
      L10n.text("Delete Theme?"),
      isPresented: Binding(
        get: { themeToDelete != nil },
        set: { if !$0 { themeToDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(L10n.text("Delete Theme"), role: .destructive) {
        if let themeToDelete { model.deleteTheme(themeToDelete) }
        themeToDelete = nil
      }
      Button(L10n.text("Cancel"), role: .cancel) { themeToDelete = nil }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 5) {
        Label("Dream Skin", systemImage: "paintpalette.fill")
          .font(.title2.weight(.semibold))
        Text(L10n.text("Codex Appearance Console"))
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 10) {
        Label(model.activity, systemImage: model.status.isActive ? "checkmark.circle.fill" : "circle.dotted")
          .foregroundStyle(statusColor)
        HStack {
          Text("Codex")
          Spacer()
          Text(model.status.codexRunning ? L10n.text("Open") : L10n.text("Closed"))
            .foregroundStyle(.secondary)
        }
        HStack {
          Text(L10n.text("Debug Port"))
          Spacer()
          Text("\(model.status.port)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)

      Spacer()

      Button {
        Task { await model.refresh() }
      } label: {
        Label(L10n.text("Refresh Status"), systemImage: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .disabled(model.isWorking)
    }
    .padding(24)
    .frame(width: 230)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
  }

  private var mainContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.status.themeName.isEmpty ? L10n.text("Current Theme") : model.status.themeName)
            .font(.title.weight(.semibold))
          Text(model.engineSummary)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker(L10n.text("Content"), selection: $selectedSection) {
          ForEach(LibrarySection.allCases) { section in
            Label(section.title, systemImage: section.icon).tag(section)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 250)
        if model.isWorking {
          ProgressView().controlSize(.small)
        }
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 22)

      Divider()

      ScrollView {
        if selectedSection == .local {
          VStack(alignment: .leading, spacing: 26) {
            controls
            themes
            if !model.lastOutput.isEmpty { latestOutput }
          }
          .padding(28)
        } else {
          onlineGallery
            .padding(28)
        }
      }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("Controls"))
        .font(.headline)
      HStack(spacing: 10) {
        if !model.isInstalled {
          Button { Task { await model.install() } } label: {
            Label(L10n.text("Install Engine"), systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.borderedProminent)
        } else {
          Button { Task { await model.apply() } } label: {
            Label(
              model.status.isActive ? L10n.text("Reapply") : L10n.text("Start Skin"),
              systemImage: "play.fill"
            )
          }
          .buttonStyle(.borderedProminent)

          Button { Task { await model.pause() } } label: {
            Label(L10n.text("Stop Skin"), systemImage: "pause.fill")
          }
          .disabled(!model.status.isActive && !model.status.isPaused)

          Button { Task { await model.importImage() } } label: {
            Label(L10n.text("Choose Background"), systemImage: "photo")
          }

          if model.engineNeedsUpdate {
            Button { Task { await model.install() } } label: {
              Label(L10n.text("Update Engine"), systemImage: "arrow.down.circle")
            }
          }

          Spacer()

          Button(role: .destructive) { showRestoreConfirmation = true } label: {
            Label(L10n.text("Restore Official Appearance"), systemImage: "arrow.uturn.backward")
          }
        }
      }
      .controlSize(.large)
      .disabled(model.isWorking)
    }
  }

  private var themes: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(L10n.text("Saved Themes"))
          .font(.headline)
        Spacer()
        Button { model.openThemeFolder() } label: {
          Image(systemName: "folder")
        }
        .buttonStyle(.borderless)
        .help(L10n.text("Open theme folder"))
      }

      if model.themes.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text(L10n.text("No Themes Yet"))
            .font(.headline)
          Text(L10n.text("Install the engine or choose a background image to create a theme."))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
      } else {
        let localThemes = model.themes.filter { $0.sourceURL == nil }
        let downloadedThemes = model.themes.filter { $0.sourceURL != nil }
        VStack(alignment: .leading, spacing: 18) {
          if !localThemes.isEmpty {
            Text(L10n.text("Local Wallpapers")).font(.subheadline.weight(.semibold))
            themeGrid(localThemes)
          }
          if !downloadedThemes.isEmpty {
            Text(L10n.text("Downloaded Wallpapers")).font(.subheadline.weight(.semibold))
            themeGrid(downloadedThemes)
          }
        }
      }
    }
  }

  private func themeGrid(_ items: [SavedTheme]) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
      ForEach(items) { theme in
        ThemeTile(
          theme: theme,
          isCurrent: theme.name == model.status.themeName,
          action: { Task { await model.switchTheme(theme) } },
          deleteAction: { themeToDelete = theme }
        )
        .disabled(model.isWorking || !model.isInstalled)
      }
    }
  }

  private var latestOutput: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text("Recent Activity"))
        .font(.headline)
      Text(model.lastOutput)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
  }

  private var onlineGallery: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker(L10n.text("Gallery Source"), selection: $onlineSource) {
        ForEach(OnlineGallerySource.allCases) { source in
          Text(source.title).tag(source)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      HStack(spacing: 10) {
        if onlineSource == .wikimedia {
          TextField(L10n.text("Search for a scene or style"), text: $onlineQuery)
            .textFieldStyle(.roundedBorder)
            .onSubmit { searchOnline() }
          Button(action: searchOnline) { Image(systemName: "magnifyingglass") }
            .buttonStyle(.borderedProminent)
            .help(L10n.text("Search online gallery"))
            .disabled(model.isSearchingOnline)
          Menu {
            ForEach(OnlineSuggestion.allCases) { suggestion in
              Button(suggestion.title) {
                onlineQuery = suggestion.query
                searchOnline()
              }
            }
          } label: {
            Label(L10n.text("Ideas"), systemImage: "sparkles")
          }
          .fixedSize()
        } else {
          Button { Task { await model.loadCommunityWallpapers() } } label: {
            Label(L10n.text("Load Community Gallery"), systemImage: "arrow.clockwise")
          }
          .buttonStyle(.borderedProminent)
          Button(action: model.openCommunitySubmission) {
            Label(L10n.text("Submit Wallpaper"), systemImage: "square.and.arrow.up")
          }
          Spacer()
        }
      }

      HStack(spacing: 8) {
        if model.isSearchingOnline { ProgressView().controlSize(.small) }
        Text(model.onlineMessage)
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        Text(onlineSource == .wikimedia ? "Wikimedia Commons" : "GitHub Community")
          .font(.caption)
          .foregroundStyle(.tertiary)
        if !displayedOnlineWallpapers.isEmpty {
          Button(action: refreshOnline) {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .help(L10n.text("Refresh Online Gallery"))
          .disabled(model.isSearchingOnline)
        }
        if model.engineNeedsUpdate {
          Button { Task { await model.install() } } label: {
            Label(L10n.text("Update Engine"), systemImage: "arrow.down.circle")
          }
          .disabled(model.isWorking)
        }
      }

      if displayedOnlineWallpapers.isEmpty && !model.isSearchingOnline {
        VStack(spacing: 10) {
          Image(systemName: "globe.americas.fill")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text(L10n.text("Online Wallpapers"))
            .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
          ForEach(displayedOnlineWallpapers) { wallpaper in
            let downloaded = model.downloadedTheme(for: wallpaper)
            OnlineWallpaperTile(
              wallpaper: wallpaper,
              downloadStatus: model.onlineDownloads[wallpaper.id],
              isDownloaded: downloaded != nil,
              isCurrent: downloaded?.name == model.status.themeName,
              primaryAction: {
                if downloaded == nil { model.downloadOnlineWallpaper(wallpaper) }
                else { Task { await model.applyOnlineWallpaper(wallpaper) } }
              },
              pauseAction: { model.pauseOnlineDownload(wallpaper.id) },
              resumeAction: { model.resumeOnlineDownload(wallpaper.id) },
              cancelAction: { model.cancelOnlineDownload(wallpaper.id) }
            )
            .disabled(!model.isInstalled)
          }
        }
      }
    }
  }

  private func searchOnline() {
    Task { await model.searchOnlineWallpapers(onlineQuery) }
  }

  private var displayedOnlineWallpapers: [OnlineWallpaper] {
    onlineSource == .wikimedia ? model.onlineWallpapers : model.communityWallpapers
  }

  private func refreshOnline() {
    if onlineSource == .wikimedia { searchOnline() }
    else { Task { await model.loadCommunityWallpapers() } }
  }
}

private enum OnlineGallerySource: CaseIterable, Identifiable {
  case wikimedia
  case community
  var id: Self { self }
  var title: String {
    self == .wikimedia ? L10n.text("Wikimedia") : L10n.text("Community")
  }
}

private enum LibrarySection: String, CaseIterable, Identifiable {
  case local
  case online

  var id: Self { self }
  var title: String {
    switch self {
    case .local: return L10n.text("Local Themes")
    case .online: return L10n.text("Online Gallery")
    }
  }
  var icon: String { self == .local ? "rectangle.stack" : "globe" }
}

private enum OnlineSuggestion: String, CaseIterable, Identifiable {
  case nature
  case city
  case space
  case ocean
  case architecture
  case romanticPortrait

  var id: Self { self }
  var title: String {
    switch self {
    case .nature: return L10n.text("Nature")
    case .city: return L10n.text("City at Night")
    case .space: return L10n.text("Space")
    case .ocean: return L10n.text("Ocean")
    case .architecture: return L10n.text("Architecture")
    case .romanticPortrait: return L10n.text("Romantic Portrait")
    }
  }
  var query: String {
    switch self {
    case .nature: return "dramatic mountain lake"
    case .city: return "city skyline night"
    case .space: return "nebula deep space"
    case .ocean: return "ocean coast aerial"
    case .architecture: return "modern architecture panorama"
    case .romanticPortrait: return "romantic cinematic portrait cherry blossoms adult woman"
    }
  }
}

private struct OnlineWallpaperTile: View {
  let wallpaper: OnlineWallpaper
  let downloadStatus: OnlineDownloadStatus?
  let isDownloaded: Bool
  let isCurrent: Bool
  let primaryAction: () -> Void
  let pauseAction: () -> Void
  let resumeAction: () -> Void
  let cancelAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ZStack(alignment: .bottom) {
        CachedRemoteImage(url: wallpaper.thumbnailURL)
        if let downloadStatus {
          VStack(spacing: 6) {
            if downloadStatus.isProcessing {
              HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.text("Saving Theme…"))
              }
            } else {
              ProgressView(value: downloadStatus.progress)
              HStack {
                Text(downloadStatus.progress.formatted(.percent.precision(.fractionLength(0))))
                  .monospacedDigit()
                Spacer()
                Button(action: downloadStatus.isPaused ? resumeAction : pauseAction) {
                  Image(systemName: downloadStatus.isPaused ? "play.fill" : "pause.fill")
                }
                .help(downloadStatus.isPaused
                  ? L10n.text("Resume Download")
                  : L10n.text("Pause Download"))
                Button(role: .cancel, action: cancelAction) {
                  Image(systemName: "xmark")
                }
                .help(L10n.text("Cancel Download"))
              }
            }
          }
          .font(.caption)
          .padding(8)
          .background(.regularMaterial)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 132)
      .background(Color(nsColor: .quaternaryLabelColor))
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 5))

      Text(wallpaper.title)
        .font(.callout.weight(.medium))
        .lineLimit(1)

      HStack(spacing: 6) {
        Text(wallpaper.resolution)
        Text("·")
        Text(wallpaper.license)
          .lineLimit(1)
        Spacer()
        Link(destination: wallpaper.detailsURL) {
          Image(systemName: "info.circle")
        }
        .help(L10n.text("View image source and license"))
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Text(wallpaper.artist)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)

      Button(action: primaryAction) {
        Label(
          isCurrent ? L10n.text("Applied") : isDownloaded ? L10n.text("Apply") : L10n.text("Download"),
          systemImage: isCurrent ? "checkmark" : isDownloaded ? "paintbrush" : "arrow.down.to.line"
        )
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .disabled(downloadStatus != nil || isCurrent)
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    }
  }
}

private struct ThemeTile: View {
  let theme: SavedTheme
  let isCurrent: Bool
  let action: () -> Void
  let deleteAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button(action: action) {
        VStack(alignment: .leading, spacing: 9) {
          ZStack {
            Color(nsColor: .quaternaryLabelColor)
            if let url = theme.imageURL, let image = NSImage(contentsOf: url) {
              Image(nsImage: image)
                .resizable()
                .scaledToFill()
            } else {
              Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
            }
          }
          .frame(height: 96)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: 5))

          HStack {
            Text(theme.name)
              .lineLimit(1)
            Spacer()
            if isCurrent {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }
          .font(.callout.weight(.medium))
        }
      }
      .buttonStyle(.plain)

      HStack {
        if let sourceURL = theme.sourceURL {
          Link(destination: sourceURL) { Image(systemName: "info.circle") }
            .help([theme.sourceAuthor, theme.sourceLicense].compactMap { $0 }.joined(separator: " · "))
        }
        Spacer()
        Button(role: .destructive, action: deleteAction) { Image(systemName: "trash") }
          .buttonStyle(.borderless)
          .help(L10n.text("Delete Theme"))
      }
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .stroke(isCurrent ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isCurrent ? 2 : 1)
    }
  }
}
