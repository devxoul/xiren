import AVFoundation
import Combine
import Foundation
import Testing
@testable import Xiren

struct MediaPlaybackTests {
  @Test func playerRejectsAFileThatIsNotAVideo() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    try Data("<html>not a video</html>".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    await #expect(throws: EzvilleError.self) { _ = try await MediaFeed.player(for: file) }
  }

  @Test func playbackFailureAfterPlayerCreationIsReported() {
    let item = AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent/clip.mp4"))
    var reported: [any Error] = []
    let subscription = MediaFeed.playbackFailures(of: item).sink { reported.append($0) }
    defer { subscription.cancel() }

    let failure = URLError(.cannotDecodeContentData)
    NotificationCenter.default.post(
      name: AVPlayerItem.failedToPlayToEndTimeNotification, object: item,
      userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: failure]
    )

    #expect(reported.count == 1)
    #expect((reported.first as? URLError)?.code == .cannotDecodeContentData)
  }
}
