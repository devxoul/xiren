import AVKit
import Combine
import Observation
import SwiftUI

/// One media list with paging and a thumbnail cache. Read-only: nothing here actuates a device.
@MainActor
@Observable
final class MediaFeed {
  let kind: MediaKind
  private(set) var items: [MediaItem] = []
  private(set) var isLoading = false
  private(set) var hasLoaded = false
  var errorMessage: String?
  private var page = 0
  private var totalPages = 1
  private var images: [MediaItem.ID: UIImage] = [:]
  private let client = EzvilleClient.shared

  init(kind: MediaKind) {
    self.kind = kind
  }

  // Loads run in their own Task: SwiftUI cancels view tasks when cells scroll away or the view
  // updates, and a cancelled URLSession request would surface as a "cancelled" error.
  func reload() async {
    await Task { await loadPage(replacing: true) }.value
  }

  func loadMore(after item: MediaItem) {
    guard item.id == items.last?.id, page < totalPages else { return }
    Task { await loadPage(replacing: false) }
  }

  private func loadPage(replacing: Bool) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let next = replacing ? 1 : page + 1
      let result = try await client.fetchMedia(kind, page: next)
      page = next
      totalPages = result.totalPages
      let known = replacing ? [] : Set(items.map(\.id))
      let fresh = result.items.filter { !known.contains($0.id) }
      items = replacing ? fresh : items + fresh
    } catch {
      errorMessage = error.localizedDescription
    }
    hasLoaded = true
  }

  /// AVPlayer prepares media asynchronously and never throws, so a clip that isn't a playable video
  /// is caught here instead of leaving a blank player.
  nonisolated static func player(for file: URL) async throws -> AVPlayer {
    let asset = AVURLAsset(url: file)
    guard (try? await asset.load(.isPlayable)) == true else { throw EzvilleError.unplayableVideo }
    return AVPlayer(playerItem: AVPlayerItem(asset: asset))
  }

  /// Failures an item reports after the player exists: a failed status while preparing or decoding,
  /// or a failure partway through playback.
  nonisolated static func playbackFailures(of item: AVPlayerItem) -> AnyPublisher<any Error, Never> {
    let failedStatus = item.publisher(for: \.status)
      .filter { $0 == .failed }
      .map { _ -> any Error in item.error ?? EzvilleError.unplayableVideo }
    let failedToEnd = NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
      .map { ($0.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? any Error) ?? EzvilleError.unplayableVideo }
    return failedStatus.merge(with: failedToEnd).eraseToAnyPublisher()
  }

  func image(for item: MediaItem) async -> UIImage? {
    if let cached = images[item.id] { return cached }
    guard let source = item.image, let data = try? await client.imageData(source), let image = UIImage(data: data) else { return nil }
    images[item.id] = image
    return image
  }
}

struct MediaView: View {
  @State private var kind: MediaKind = .visitors
  @State private var visitors = MediaFeed(kind: .visitors)
  @State private var recordings = MediaFeed(kind: .recordings)

  var body: some View {
    NavigationStack {
      MediaGrid(feed: kind == .visitors ? visitors : recordings)
        .id(kind)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("CCTV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            Picker("List", selection: $kind) {
              Text("Visitors").tag(MediaKind.visitors)
              Text("Recordings").tag(MediaKind.recordings)
            }
            .pickerStyle(.segmented)
            .fixedSize()
          }
        }
    }
  }
}

private struct MediaGrid: View {
  @Bindable var feed: MediaFeed
  @State private var selected: MediaItem?

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
        ForEach(feed.items) { item in
          Button { selected = item } label: { MediaCell(feed: feed, item: item) }
            .buttonStyle(.plain)
            .onAppear { feed.loadMore(after: item) }
        }
      }
      .padding()

      if feed.isLoading {
        ProgressView().padding()
      } else if feed.hasLoaded && feed.items.isEmpty {
        ContentUnavailableView {
          Label(feed.kind == .visitors ? "No Visitors" : "No Recordings", systemImage: feed.kind == .visitors ? "person.crop.rectangle" : "video.slash")
        } description: {
          Text("Pull to refresh.")
        }
      }
    }
    .refreshable { await feed.reload() }
    .task { if !feed.hasLoaded { await feed.reload() } }
    .sheet(item: $selected) { item in MediaDetailView(feed: feed, item: item) }
    .alert("Error", isPresented: Binding(get: { feed.errorMessage != nil }, set: { if !$0 { feed.errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(feed.errorMessage ?? "")
    }
  }
}

private struct MediaCell: View {
  let feed: MediaFeed
  let item: MediaItem
  @State private var image: UIImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Color(.secondarySystemGroupedBackground)
        .aspectRatio(4 / 3, contentMode: .fit)
        .overlay {
          if let image {
            Image(uiImage: image).resizable().scaledToFill()
          } else {
            Image(systemName: item.movie == nil ? "photo" : "video").foregroundStyle(.secondary)
          }
        }
        .overlay(alignment: .bottomTrailing) {
          if item.movie != nil {
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white).shadow(radius: 2).padding(6)
          }
        }
        .clipShape(.rect(cornerRadius: 12))
      Text(item.date?.formatted(date: .abbreviated, time: .shortened) ?? item.filename)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .task(id: item.id) { image = await feed.image(for: item) }
  }
}

private struct MediaDetailView: View {
  let feed: MediaFeed
  let item: MediaItem
  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?
  @State private var player: AVPlayer?
  @State private var error: String?

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        if let player {
          VideoPlayer(player: player)
        } else if let error {
          ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(error))
            .foregroundStyle(.white)
        } else if let image, item.movie == nil {
          Image(uiImage: image).resizable().scaledToFit()
        } else {
          ProgressView().tint(.white)
        }
      }
      .navigationTitle(item.date?.formatted(date: .abbreviated, time: .shortened) ?? item.filename)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .task {
      if let movie = item.movie {
        do {
          let player = try await MediaFeed.player(for: try await EzvilleClient.shared.movieFile(movie))
          self.player = player
          player.play()
          if let item = player.currentItem {
            for await failure in MediaFeed.playbackFailures(of: item).values {
              self.player = nil
              self.error = failure.localizedDescription
              break
            }
          }
        } catch {
          self.error = error.localizedDescription
        }
      } else {
        image = await feed.image(for: item)
        if image == nil { error = String(localized: "The photo is unavailable.") }
      }
    }
    .onDisappear { player?.pause() }
  }
}
