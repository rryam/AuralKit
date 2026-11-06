import Foundation
import AVFoundation
import Speech
import Testing
@testable import AuralKit

private actor AssetGate {
    private var entered = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let pending = arrivals
        arrivals.removeAll()
        for arrival in pending { arrival.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitForEntry() async {
        guard !entered else { return }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor AssetInventoryProbe {
    struct Snapshot: Sendable {
        let locales: Set<String>
        let reserves: [String]
        let releases: [String]
    }

    private var stored: [String: Locale]
    private let variants: [String: Locale]
    private var reserveCalls: [String] = []
    private var releaseCalls: [String] = []
    private var reserveGate: AssetGate?
    private var releaseGate: AssetGate?
    private var extraLocales: [Locale] = []

    init(initial: [Locale] = [], variants: [String: Locale] = [:]) {
        stored = Dictionary(initial.map { ($0.identifier(.bcp47), $0) },
                            uniquingKeysWith: { first, _ in first })
        self.variants = variants
    }

    nonisolated var client: SpeechAssetReservations.Inventory {
        .init(locales: { await self.locales() },
              reserve: { await self.reserve($0) },
              release: { await self.release($0) })
    }

    var snapshot: Snapshot {
        Snapshot(locales: Set(stored.keys), reserves: reserveCalls, releases: releaseCalls)
    }

    func holdReserve(at gate: AssetGate) { reserveGate = gate }
    func holdRelease(at gate: AssetGate) { releaseGate = gate }
    func addDuringNextReserve(_ locales: [Locale]) { extraLocales = locales }
    private func locales() -> [Locale] { Array(stored.values) }

    private func reserve(_ locale: Locale) async -> Bool {
        let requested = locale.identifier(.bcp47)
        reserveCalls.append(requested)
        await reserveGate?.wait()
        let actual = variants[requested] ?? locale
        let key = actual.identifier(.bcp47)
        guard stored[key] == nil else { return false }
        stored[key] = actual
        for extra in extraLocales { stored[extra.identifier(.bcp47)] = extra }
        extraLocales.removeAll()
        return true
    }

    private func release(_ locale: Locale) async -> Bool {
        let key = locale.identifier(.bcp47)
        releaseCalls.append(key)
        await releaseGate?.wait()
        return stored.removeValue(forKey: key) != nil
    }
}

@MainActor
private final class AssetReservationFixture {
    let inventory: AssetInventoryProbe
    let reservations: SpeechAssetReservations
    private var gates: [AssetGate] = []
    private var acquisitions: [Task<SpeechAssetReservations.Lease, Error>] = []
    private var work: [Task<Void, Error>] = []
    private var releases: [Task<Void, Never>] = []
    private var managers: [ModelManager] = []

    init(initial: [Locale] = [], variants: [String: Locale] = [:]) {
        let inventory = AssetInventoryProbe(initial: initial, variants: variants)
        self.inventory = inventory
        reservations = SpeechAssetReservations(inventory: inventory.client)
    }

    func gate() -> AssetGate {
        let gate = AssetGate()
        gates.append(gate)
        return gate
    }

    func acquire(_ locale: Locale) -> Task<SpeechAssetReservations.Lease, Error> {
        let task = Task { try await reservations.acquire(locale) }
        acquisitions.append(task)
        return task
    }

    func start(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let task = Task { try await operation() }
        work.append(task)
        return task
    }

    func release(_ lease: SpeechAssetReservations.Lease) -> Task<Void, Never> {
        let task = Task { await reservations.release(lease) }
        releases.append(task)
        return task
    }

    func manager(
        download: @escaping @Sendable ([any SpeechModule]) async throws -> Void
    ) -> ModelManager {
        let manager = ModelManager(reservations: reservations, assetDownloader: download)
        managers.append(manager)
        return manager
    }

    func release(_ manager: ModelManager) async -> Task<Void, Never> {
        let task = await manager.beginReleasingLocales()
        releases.append(task)
        return task
    }

    func cleanup() async {
        for task in acquisitions { task.cancel() }
        for task in work { task.cancel() }
        for gate in gates { await gate.open() }
        for task in work { _ = await task.result }
        for manager in managers { await manager.releaseLocales() }
        for task in acquisitions {
            if case .success(let lease) = await task.result { await reservations.release(lease) }
        }
        for task in releases { await task.value }
    }

    enum ProbeError: Error { case download }
}

/// Only module metadata is needed by ModelManager. No native provider is invoked.
private final class ReservationModule: LocaleDependentSpeechModule {
    struct Result: SpeechModuleResult, Sendable {
        let range = CMTimeRange.zero
        let resultsFinalizationTime = CMTime.zero
    }

    let selectedLocales: [Locale]
    init(locales: [Locale]) { selectedLocales = locales }

    static var supportedLocales: [Locale] { get async { [] } }
    static func supportedLocale(equivalentTo locale: Locale) async -> Locale? { nil }
    var availableCompatibleAudioFormats: [AVAudioFormat] { get async { [] } }
    var results: AsyncThrowingStream<Result, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@Suite("Speech asset reservations")
struct SpeechAssetReservationTests {
    @Test("concurrent sessions share acquisition and only the final owner releases")
    @MainActor
    func concurrentOwners() async throws {
        try await withFixture { fixture in
            let gate = fixture.gate()
            await fixture.inventory.holdReserve(at: gate)
            let first = fixture.acquire(Locale(identifier: "en-US"))
            await gate.waitForEntry()
            let second = fixture.acquire(Locale(identifier: "en-US"))
            await gate.open()
            let firstLease = try await first.value
            let secondLease = try await second.value
            await fixture.reservations.release(firstLease)
            var state = await fixture.inventory.snapshot
            #expect(state.reserves == ["en-US"])
            #expect(state.releases.isEmpty)
            await fixture.reservations.release(secondLease)
            state = await fixture.inventory.snapshot
            #expect(state.releases == ["en-US"])
            #expect(state.locales.isEmpty)
        }
    }

    @Test("managers retain module-selected locales until the last holder releases")
    @MainActor
    func managerHolders() async throws {
        try await withFixture { fixture in
            let module = ReservationModule(locales: [Locale(identifier: "ja-JP")])
            let first = fixture.manager { _ in }
            let second = fixture.manager { _ in }
            // The explicit locale is not a substitute for module-selected asset identity.
            try await first.ensureModel(module: module, locale: Locale(identifier: "en-US"))
            try await second.ensureAssets(for: [module])
            await first.releaseLocales()
            await first.releaseLocales()
            var state = await fixture.inventory.snapshot
            #expect(state.reserves == ["ja-JP"])
            #expect(state.releases.isEmpty)
            await second.releaseLocales()
            state = await fixture.inventory.snapshot
            #expect(state.releases == ["ja-JP"])
            #expect(state.locales.isEmpty)
        }
    }

    @Test("release uses the observed native locale variant")
    @MainActor
    func canonicalVariant() async throws {
        try await withFixture(variants: ["en-AU": Locale(identifier: "en-US")]) { fixture in
            let lease = try await fixture.acquire(Locale(identifier: "en-AU")).value
            let canonical = try await fixture.acquire(Locale(identifier: "en-US")).value
            let alias = try await fixture.acquire(Locale(identifier: "en-AU")).value
            await fixture.reservations.release(lease)
            await fixture.reservations.release(canonical)
            #expect(await fixture.inventory.snapshot.releases.isEmpty)
            await fixture.reservations.release(alias)
            let state = await fixture.inventory.snapshot
            #expect(state.reserves == ["en-AU"])
            #expect(state.releases == ["en-US"])
            #expect(state.locales.isEmpty)
        }
    }

    @Test("preexisting variant reservations remain borrowed")
    @MainActor
    func preexistingReservation() async throws {
        try await withFixture(initial: [Locale(identifier: "en-US")],
                              variants: ["en-AU": Locale(identifier: "en-US")]) { fixture in
            let lease = try await fixture.acquire(Locale(identifier: "en-AU")).value
            await fixture.reservations.release(lease)
            let state = await fixture.inventory.snapshot
            #expect(state.releases.isEmpty)
            #expect(state.locales == ["en-US"])
        }
    }

    @Test("an externally reserved exact locale survives manager cleanup")
    @MainActor
    func externalManagerReservation() async throws {
        try await withFixture(initial: [Locale(identifier: "en-US")]) { fixture in
            let module = ReservationModule(locales: [Locale(identifier: "en-US")])
            let manager = fixture.manager { _ in }
            try await manager.ensureAssets(for: [module])
            await manager.releaseLocales()
            let state = await fixture.inventory.snapshot
            #expect(state.reserves.isEmpty)
            #expect(state.releases.isEmpty)
            #expect(state.locales == ["en-US"])
        }
    }

    @Test("a borrowed alias conservatively protects all current owned candidates")
    @MainActor
    func multipleAliasCandidates() async throws {
        try await withFixture(variants: ["en-AU": Locale(identifier: "en-US")]) { fixture in
            let english = try await fixture.acquire(Locale(identifier: "en-US")).value
            let japanese = try await fixture.acquire(Locale(identifier: "ja-JP")).value
            let alias = try await fixture.acquire(Locale(identifier: "en-AU")).value
            await fixture.reservations.release(english)
            await fixture.reservations.release(japanese)
            #expect(await fixture.inventory.snapshot.releases.isEmpty)
            await fixture.reservations.release(alias)
            let state = await fixture.inventory.snapshot
            #expect(Set(state.releases) == ["en-US", "ja-JP"])
            #expect(state.locales.isEmpty)
        }
    }

    @Test("unknown borrowed aliases protect current candidates, not future unrelated assets")
    @MainActor
    func ambiguousBorrower() async throws {
        try await withFixture(variants: ["en-AU": Locale(identifier: "en-US")]) { fixture in
            let owner = try await fixture.acquire(Locale(identifier: "en-US")).value
            let borrower = try await fixture.acquire(Locale(identifier: "en-AU")).value
            let later = try await fixture.acquire(Locale(identifier: "ja-JP")).value
            await fixture.reservations.release(owner)
            var state = await fixture.inventory.snapshot
            #expect(state.releases.isEmpty)
            await fixture.reservations.release(later)
            state = await fixture.inventory.snapshot
            #expect(state.releases == ["ja-JP"])
            await fixture.reservations.release(borrower)
            state = await fixture.inventory.snapshot
            #expect(state.releases == ["ja-JP", "en-US"])
        }
    }

    @Test("ambiguous native mutations are not claimed or broadly released")
    @MainActor
    func ambiguousInventoryMutation() async throws {
        try await withFixture { fixture in
            await fixture.inventory.addDuringNextReserve([Locale(identifier: "fr-FR")])
            let operation = fixture.acquire(Locale(identifier: "en-US"))
            if case .success = await operation.result { Issue.record("Ambiguous inventory was accepted") }
            let state = await fixture.inventory.snapshot
            #expect(state.releases.isEmpty)
            #expect(state.locales == ["en-US", "fr-FR"])
        }
    }

    @Test("reacquisition during release waits and establishes a fresh reservation")
    @MainActor
    func reacquisitionDuringRelease() async throws {
        try await withFixture { fixture in
            let lease = try await fixture.acquire(Locale(identifier: "en-US")).value
            let gate = fixture.gate()
            await fixture.inventory.holdRelease(at: gate)
            let release = fixture.release(lease)
            await gate.waitForEntry()
            let next = fixture.acquire(Locale(identifier: "en-US"))
            await gate.open()
            await release.value
            let nextLease = try await next.value
            var state = await fixture.inventory.snapshot
            #expect(state.reserves == ["en-US", "en-US"])
            #expect(state.locales == ["en-US"])
            await fixture.reservations.release(nextLease)
            state = await fixture.inventory.snapshot
            #expect(state.releases == ["en-US", "en-US"])
        }
    }

    @Test("manager download failure returns its explicitly acquired locale")
    @MainActor
    func downloadFailure() async throws {
        try await withFixture { fixture in
            let module = ReservationModule(locales: [Locale(identifier: "en-US")])
            let manager = fixture.manager { _ in throw AssetReservationFixture.ProbeError.download }
            let operation = fixture.start {
                do {
                    try await manager.ensureAssets(for: [module])
                } catch {
                    await manager.releaseLocales()
                    throw error
                }
            }
            if case .success = await operation.result { Issue.record("Download failure was ignored") }
            let state = await fixture.inventory.snapshot
            #expect(!state.reserves.isEmpty)
            #expect(state.releases.count == state.reserves.count)
            #expect(state.locales.isEmpty)
        }
    }

    @Test("canceling manager acquisition cannot abandon a late native reservation")
    @MainActor
    func canceledAcquisition() async throws {
        try await withFixture { fixture in
            let gate = fixture.gate()
            await fixture.inventory.holdReserve(at: gate)
            let module = ReservationModule(locales: [Locale(identifier: "en-US")])
            let manager = fixture.manager { _ in Issue.record("Canceled acquisition started a download") }
            let operation = fixture.start { try await manager.ensureAssets(for: [module]) }
            await gate.waitForEntry()
            operation.cancel()
            await gate.open()
            if case .success = await operation.result { Issue.record("Canceled acquisition succeeded") }
            let state = await fixture.inventory.snapshot
            #expect(state.releases.count == 1)
            #expect(state.locales.isEmpty)
        }
    }

    @Test("cancellation after acquisition returns the lease when preparation unwinds")
    @MainActor
    func canceledPreparation() async throws {
        try await withFixture { fixture in
            let gate = fixture.gate()
            let module = ReservationModule(locales: [Locale(identifier: "en-US")])
            let manager = fixture.manager { _ in await gate.wait() }
            let operation = fixture.start { try await manager.ensureAssets(for: [module]) }
            await gate.waitForEntry()
            operation.cancel()
            #expect(await fixture.inventory.snapshot.releases.isEmpty)
            await gate.open()
            switch await operation.result {
            case .failure(is CancellationError): break
            default: Issue.record("Canceled preparation did not throw CancellationError")
            }
            let state = await fixture.inventory.snapshot
            #expect(state.releases == ["en-US"])
            #expect(state.locales.isEmpty)
        }
    }

    @Test("manager cleanup drains pending acquisitions before returning")
    @MainActor
    func cleanupDuringAcquisition() async throws {
        try await withFixture { fixture in
            let gate = fixture.gate()
            await fixture.inventory.holdReserve(at: gate)
            let module = ReservationModule(locales: [Locale(identifier: "en-US")])
            let manager = fixture.manager { _ in Issue.record("Retired preparation started a download") }
            let operation = fixture.start { try await manager.ensureAssets(for: [module]) }
            await gate.waitForEntry()
            let cleanup = await fixture.release(manager)
            let repeated = await fixture.release(manager)
            await gate.open()
            if case .success = await operation.result { Issue.record("Retired acquisition succeeded") }
            await repeated.value
            await cleanup.value
            let state = await fixture.inventory.snapshot
            #expect(state.releases.count == 1)
            #expect(state.locales.isEmpty)
        }
    }

    @Test("manager cleanup retains reservations until an active download returns")
    @MainActor
    func cleanupDuringDownload() async throws {
        try await withFixture { fixture in
            let gate = fixture.gate()
            let module = ReservationModule(locales: [Locale(identifier: "en-US")])
            let manager = fixture.manager { _ in await gate.wait() }
            let operation = fixture.start { try await manager.ensureAssets(for: [module]) }
            await gate.waitForEntry()
            let cleanup = await fixture.release(manager)
            let repeated = await fixture.release(manager)
            let peer = fixture.manager { _ in }
            try await peer.ensureAssets(for: [module])
            // Admission stays closed while cleanup is joining preparation.
            let rejected = fixture.start { try await manager.ensureAssets(for: [module]) }
            if case .success = await rejected.result { Issue.record("Cleanup admitted new preparation") }
            var state = await fixture.inventory.snapshot
            #expect(state.releases.isEmpty)
            await gate.open()
            if case .success = await operation.result { Issue.record("Retired download was admitted") }
            await cleanup.value
            await repeated.value
            state = await fixture.inventory.snapshot
            #expect(state.releases.isEmpty)
            // A retired holder's repeated cleanup cannot return a peer's lease.
            await manager.releaseLocales()
            await peer.releaseLocales()
            state = await fixture.inventory.snapshot
            #expect(state.releases.count == 1)
            #expect(state.locales.isEmpty)
        }
    }

    @MainActor
    private func withFixture(
        initial: [Locale] = [], variants: [String: Locale] = [:],
        operation: @MainActor (AssetReservationFixture) async throws -> Void
    ) async throws {
        let fixture = AssetReservationFixture(initial: initial, variants: variants)
        do {
            try await operation(fixture)
        } catch {
            await fixture.cleanup()
            throw error
        }
        await fixture.cleanup()
    }
}
