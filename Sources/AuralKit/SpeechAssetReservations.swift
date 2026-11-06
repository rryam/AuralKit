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
        fileprivate let id: UUID
    }

    enum ReservationError: Error {
        case ambiguousInventoryChange
    }

    private struct Reservation {
        let locale: Locale
        var holders: Set<UUID> = []
    }

    private struct Alias {
        let protectedKeys: Set<String>
        var holders: Set<UUID> = []
    }

    private struct Holding {
        let alias: String
        let protectedKeys: Set<String>
    }

    static let shared = SpeechAssetReservations()

    private let inventory: Inventory
    private var reservations: [String: Reservation] = [:]
    private var aliases: [String: Alias] = [:]
    private var holdings: [UUID: Holding] = [:]
    private var tail: Task<Void, Never>?
    private var queuedOperations = 0

    init(inventory: Inventory = .live) {
        self.inventory = inventory
    }

    func acquire(_ locale: Locale) async throws -> Lease {
        try Task.checkCancellation()
        let previous = tail
        queuedOperations += 1
        let operation = Task {
            await previous?.value
            return try await self.acquireSerially(locale)
        }
        tail = Task {
            _ = await operation.result
            self.operationFinished()
        }
        let lease = try await operation.value
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
        let previous = tail
        queuedOperations += 1
        let operation = Task {
            await previous?.value
            await self.releaseSerially(lease)
        }
        tail = Task {
            await operation.value
            self.operationFinished()
        }
        await operation.value
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
        if let known = aliases[alias] {
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
                reservations[key] = Reservation(locale: actual)
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
        let lease = Lease(id: UUID())
        var entry = aliases[alias] ?? Alias(protectedKeys: keys)
        entry.holders.insert(lease.id)
        aliases[alias] = entry
        holdings[lease.id] = Holding(alias: alias, protectedKeys: keys)
        for key in keys {
            reservations[key]?.holders.insert(lease.id)
        }
        return lease
    }

    private func releaseSerially(_ lease: Lease) async {
        guard let holding = holdings.removeValue(forKey: lease.id) else { return }
        aliases[holding.alias]?.holders.remove(lease.id)
        if aliases[holding.alias]?.holders.isEmpty == true {
            aliases.removeValue(forKey: holding.alias)
        }
        for key in holding.protectedKeys {
            reservations[key]?.holders.remove(lease.id)
        }
        for key in holding.protectedKeys {
            guard let reservation = reservations[key], reservation.holders.isEmpty else { continue }
            reservations.removeValue(forKey: key)
            _ = await inventory.release(reservation.locale)
        }
    }

    private static func key(_ locale: Locale) -> String {
        locale.identifier(.bcp47)
    }

    private static func index(_ locales: [Locale]) -> [String: Locale] {
        Dictionary(locales.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }
}
