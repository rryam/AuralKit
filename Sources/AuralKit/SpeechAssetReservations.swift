import Foundation
import Speech

/// Coordinates reservation mutations made through AuralKit's shared instance.
/// Its native inventory calls are serialized across suspension points, not merely
/// isolated to an actor. Unrelated AssetInventory clients are outside this queue.
/// Existing reservations are borrowed, never reclaimed.
actor SpeechAssetReservations {
    struct Inventory: Sendable {
        var locales: @Sendable () async -> [Locale]
        var reserve: @Sendable (Locale) async throws -> Bool
        var release: @Sendable (Locale) async -> Bool

        static let live = Inventory(
            locales: { await AssetInventory.reservedLocales },
            reserve: { try await AssetInventory.reserve(locale: $0) },
            release: { await AssetInventory.release(reservedLocale: $0) }
        )
    }

    struct Lease: Hashable, Sendable {
        fileprivate let id = UUID()
        fileprivate let alias: String
        fileprivate let protectedKeys: Set<String>
    }

    enum ReservationError: Error {
        case ambiguousInventoryChange
    }

    static let shared = SpeechAssetReservations()

    private let inventory: Inventory
    private var reservations: [String: Locale] = [:]
    private var leases: Set<Lease> = []
    private var tail: Task<Void, Never>?
    private(set) var queuedOperations = 0

    init(inventory: Inventory = .live) {
        self.inventory = inventory
    }

    func acquire(_ locale: Locale) async throws -> Lease {
        try Task.checkCancellation()
        let lease = try await enqueue { try await self.acquireSerially(locale) }.value
        do {
            try Task.checkCancellation()
            return lease
        } catch {
            // A shared native reserve can finish after its caller is canceled.
            // Do not abandon the successful acquisition at that boundary.
            await release(lease)
            throw error
        }
    }

    func release(_ lease: Lease) async {
        _ = await enqueue { await self.releaseSerially(lease) }.result
    }

    /// Installation requests also reserve locales; their creation shares this queue.
    /// The subsequent download must run outside it.
    func withInventoryAccess<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let task = enqueue {
            try Task.checkCancellation()
            return try await operation()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func enqueue<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) -> Task<Value, Error> {
        let previous = tail
        queuedOperations += 1
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task {
            _ = await task.result
            self.operationFinished()
        }
        return task
    }

    private func operationFinished() {
        queuedOperations -= 1
        if queuedOperations == 0 {
            // Completed tasks must not become a retained operation history.
            tail = nil
        }
    }

    private func acquireSerially(_ locale: Locale) async throws -> Lease {
        let alias = Self.key(locale)
        if let known = leases.first(where: { $0.alias == alias }) {
            return admit(alias: alias, protecting: known.protectedKeys)
        }
        if reservations[alias] != nil {
            return admit(alias: alias, protecting: [alias])
        }

        let before = Self.index(await inventory.locales())
        if before[alias] != nil {
            // Preserve an exact external reservation without mutating it.
            return admit(alias: alias, protecting: [])
        }
        let created = try await inventory.reserve(locale)
        let after = Self.index(await inventory.locales())
        let protectedKeys: Set<String>
        if created {
            let added = Set(after.keys).subtracting(before.keys)
            // The API returns a Bool, not the canonical asset locale. Only one
            // unambiguous new native identity establishes ownership. Preserve
            // unknown reservations if another inventory client changed it.
            guard added.count == 1, let key = added.first, let actual = after[key] else {
                throw ReservationError.ambiguousInventoryChange
            }
            if reservations[key] == nil {
                reservations[key] = actual
            }
            protectedKeys = [key]
        } else if after[alias] != nil {
            // An exact native identity can be borrowed without protecting
            // unrelated reservations that this coordinator happens to own.
            protectedKeys = reservations[alias] == nil ? [] : [alias]
        } else {
            guard !after.isEmpty else { throw ReservationError.ambiguousInventoryChange }
            // Native inventory can report a variant of the requested locale.
            // Do not guess language/region equivalence. An unknown borrowed
            // alias protects only currently owned candidates until it ends.
            protectedKeys = Set(reservations.keys).intersection(after.keys)
        }
        return admit(alias: alias, protecting: protectedKeys)
    }

    private func admit(alias: String, protecting keys: Set<String>) -> Lease {
        let lease = Lease(alias: alias, protectedKeys: keys)
        leases.insert(lease)
        return lease
    }

    private func releaseSerially(_ lease: Lease) async {
        guard leases.remove(lease) != nil else { return }
        for key in lease.protectedKeys where !leases.contains(where: { $0.protectedKeys.contains(key) }) {
            guard let locale = reservations.removeValue(forKey: key) else { continue }
            _ = await inventory.release(locale)
        }
    }

    private static func key(_ locale: Locale) -> String {
        locale.identifier(.bcp47)
    }

    private static func index(_ locales: [Locale]) -> [String: Locale] {
        Dictionary(locales.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }
}
