import Foundation
@testable import AuralKit

actor AssetGate {
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

actor AssetInventoryProbe {
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
