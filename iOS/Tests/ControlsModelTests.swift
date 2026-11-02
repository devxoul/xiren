import Testing
@testable import Xiren

@MainActor
struct ControlsModelTests {
  @MainActor
  final class GatedFetch {
    private(set) var calls = 0
    private var gates: [CheckedContinuation<Void, Never>] = []
    let started: AsyncStream<Int>
    private let startedContinuation: AsyncStream<Int>.Continuation

    init() {
      (started, startedContinuation) = AsyncStream.makeStream()
    }

    func callAsFunction() async -> ControlsSnapshot {
      calls += 1
      let call = calls
      await withCheckedContinuation { gate in
        gates.append(gate)
        startedContinuation.yield(call)
      }
      return Self.snapshot(call)
    }

    func releaseNext() {
      gates.removeFirst().resume()
    }

    static func snapshot(_ call: Int) -> ControlsSnapshot {
      ControlsSnapshot(lights: [SwitchDevice(kind: .light, id: "0000001_101_101_light_1_1", zone: "거실", isOn: call.isMultiple(of: 2))])
    }
  }

  @Test func refreshRequestedDuringAFetchRunsAnotherFetchAfterIt() async {
    // given: a refresh whose fetch has started and not finished
    let fetch = GatedFetch()
    let model = ControlsModel(fetch: { await fetch() })
    var started = fetch.started.makeAsyncIterator()
    let first = model.scheduleRefresh()
    #expect(await started.next() == 1)

    // when: another control finishes and asks for a refresh mid-fetch
    let second = model.scheduleRefresh()
    fetch.releaseNext()

    // then: a second fetch starts after the first, and its result is what's shown
    #expect(await started.next() == 2)
    fetch.releaseNext()
    await first.value
    await second.value
    #expect(fetch.calls == 2)
    #expect(model.snapshot == GatedFetch.snapshot(2))
  }
}
