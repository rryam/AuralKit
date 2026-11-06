import Foundation
import Speech
import OSLog

// MARK: - Model Manager

actor ModelManager {

    private let logger = Logger(subsystem: "com.auralkit.speech", category: "ModelManager")

    private(set) var currentDownloadProgress: Progress?

    private let reservations: SpeechAssetReservations
    private let assetDownloader: (@Sendable ([any SpeechModule]) async throws -> Void)?
    private var leases: Set<SpeechAssetReservations.Lease> = []
    private var preparations = 0
    private var preparationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cleanupTask: Task<Void, Never>?

    init(
        reservations: SpeechAssetReservations = .shared,
        assetDownloader: (@Sendable ([any SpeechModule]) async throws -> Void)? = nil
    ) {
        self.reservations = reservations
        self.assetDownloader = assetDownloader
    }

    /// Ensure the speech model for the given locale is available
    func ensureModel(module: any LocaleDependentSpeechModule, locale: Locale) async throws {
        if let speechModule = module as? SpeechTranscriber {
            try await ensureLocaleAssets(
                module: speechModule,
                locale: locale,
                supportedLocales: { await SpeechTranscriber.supportedLocales },
                installedLocales: { await SpeechTranscriber.installedLocales }
            )
            return
        }

        if let dictationModule = module as? DictationTranscriber {
            try await ensureLocaleAssets(
                module: dictationModule,
                locale: locale,
                supportedLocales: { await DictationTranscriber.supportedLocales },
                installedLocales: { await DictationTranscriber.installedLocales }
            )
            return
        }

        try await prepareAssets(for: [module]) { manager in
            try await manager.downloadAssetsIfNeeded(for: [module])
        }
    }

    private func ensureLocaleAssets<Module: LocaleDependentSpeechModule>(
        module: Module,
        locale: Locale,
        supportedLocales: @escaping @Sendable () async -> [Locale],
        installedLocales: @escaping @Sendable () async -> [Locale]
    ) async throws {
        try await prepareAssets(for: [module], validate: { manager in
            guard await manager.localeMatches(provider: supportedLocales, locale: locale) else {
                throw SpeechSessionError.unsupportedLocale(locale)
            }
        }, install: { manager in
            if await manager.localeMatches(provider: installedLocales, locale: locale) {
                manager.logger.notice("Locale \(locale.identifier(.bcp47)) already installed")
                manager.currentDownloadProgress = nil
            } else {
                manager.logger.info("Ensuring model download for locale \(locale.identifier(.bcp47))")
                try await manager.downloadAssetsIfNeeded(for: [module])
            }
        })
    }

    private func localeMatches(
        provider: @escaping @Sendable () async -> [Locale],
        locale: Locale
    ) async -> Bool {
        let locales = await provider()
        let target = locale.identifier(.bcp47)
        return locales.contains { $0.identifier(.bcp47) == target }
    }

    func ensureAssets(for modules: [any SpeechModule]) async throws {
        guard !modules.isEmpty else { return }
        try await prepareAssets(for: modules) { manager in
            try await manager.downloadAssetsIfNeeded(for: modules)
        }
    }

    private func downloadAssetsIfNeeded(for modules: [any SpeechModule]) async throws {
        try requirePreparation()
        if let assetDownloader {
            try await assetDownloader(modules)
            return
        }
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try requirePreparation()
            currentDownloadProgress = downloader.progress
            logger.info("Starting asset download for \(modules.count) module(s)")
            do {
                try await downloader.downloadAndInstall()
                currentDownloadProgress = nil
                logger.notice("Asset download completed successfully")
            } catch {
                currentDownloadProgress = nil
                logger.error("Asset download failed: \(error.localizedDescription, privacy: .public)")

                // Check for network connectivity errors
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain,
                   nsError.code == URLError.notConnectedToInternet.rawValue {
                    throw SpeechSessionError.modelDownloadNoInternet
                }

                throw SpeechSessionError.modelDownloadFailed(nsError)
            }
        } else {
            currentDownloadProgress = nil
            logger.debug("No asset download required for modules")
        }
    }

    /// Close preparation admission and join it before returning locale leases.
    /// A late native acquisition/download must not outlive its manager cleanup.
    func releaseLocales() async {
        await beginReleasingLocales().value
    }

    /// Close admission synchronously on this actor; concurrent releases join one drain.
    /// Only ModelManager preparation is joined here, never its calling pipeline task:
    /// a failed setup may itself call releaseLocales after ensureModel has unwound.
    func beginReleasingLocales() -> Task<Void, Never> {
        if let cleanupTask { return cleanupTask }
        let cleanup = Task {
            if self.preparations != 0 {
                await withCheckedContinuation { self.preparationWaiters.append($0) }
            }
            let pending = self.leases
            self.leases.removeAll()
            for lease in pending {
                await self.reservations.release(lease)
            }
            self.currentDownloadProgress = nil
            self.cleanupTask = nil
            self.logger.debug("Released \(pending.count) session locale lease(s)")
        }
        cleanupTask = cleanup
        return cleanup
    }

    private func prepareAssets(
        for modules: [any SpeechModule],
        validate: @Sendable (isolated ModelManager) async throws -> Void = { _ in },
        install: @Sendable (isolated ModelManager) async throws -> Void
    ) async throws {
        try requirePreparation()
        preparations += 1
        defer { preparationFinished() }
        var acquired: [SpeechAssetReservations.Lease] = []
        do {
            try await validate(self)
            try requirePreparation()
            // These are module-defined asset locales, not guessed equivalents
            // of the user's preferred transcription language.
            let locales = modules.compactMap { $0 as? any LocaleDependentSpeechModule }
                .flatMap { $0.selectedLocales }
            var requested = Set<String>()
            for locale in locales where requested.insert(locale.identifier(.bcp47)).inserted {
                do {
                    acquired.append(try await reservations.acquire(locale))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw SpeechSessionError.modelReservationFailed(locale, error)
                }
                try requirePreparation()
            }
            try await install(self)
            try requirePreparation()
            leases.formUnion(acquired)
        } catch {
            for lease in acquired {
                await reservations.release(lease)
            }
            throw error
        }
    }

    private func requirePreparation() throws {
        try Task.checkCancellation()
        guard cleanupTask == nil else { throw CancellationError() }
    }

    private func preparationFinished() {
        preparations -= 1
        guard preparations == 0 else { return }
        let waiters = preparationWaiters
        preparationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
