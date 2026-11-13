import Foundation
import Speech
import OSLog

// MARK: - Model Manager

actor ModelManager {

    private let logger = Logger(subsystem: "com.auralkit.speech", category: "ModelManager")

    private(set) var currentDownloadProgress: Progress?

    private let reservations: SpeechAssetReservations
    private let assetDownloader: (@Sendable ([any SpeechModule]) async throws -> Void)?
    private let installationRequest: @Sendable ([any SpeechModule]) async throws -> AssetInstallationRequest?
    private var leases: Set<SpeechAssetReservations.Lease> = []
    private var generation = 0

    init(
        reservations: SpeechAssetReservations = .shared,
        assetDownloader: (@Sendable ([any SpeechModule]) async throws -> Void)? = nil,
        installationRequest: @escaping @Sendable ([any SpeechModule]) async throws -> AssetInstallationRequest? = {
            try await AssetInventory.assetInstallationRequest(supporting: $0)
        }
    ) {
        self.reservations = reservations
        self.assetDownloader = assetDownloader
        self.installationRequest = installationRequest
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

        try await prepareAssets(for: [module]) { manager, generation in
            try await manager.downloadAssetsIfNeeded(for: [module], generation: generation)
        }
    }

    private func ensureLocaleAssets<Module: LocaleDependentSpeechModule>(
        module: Module,
        locale: Locale,
        supportedLocales: @escaping @Sendable () async -> [Locale],
        installedLocales: @escaping @Sendable () async -> [Locale]
    ) async throws {
        try await prepareAssets(for: [module]) { manager, generation in
            guard await manager.localeMatches(provider: supportedLocales, locale: locale) else {
                throw SpeechSessionError.unsupportedLocale(locale)
            }
            if await manager.localeMatches(provider: installedLocales, locale: locale) {
                manager.logger.notice("Locale \(locale.identifier(.bcp47)) already installed")
                try manager.requireCurrent(generation)
                manager.currentDownloadProgress = nil
            } else {
                manager.logger.info("Ensuring model download for locale \(locale.identifier(.bcp47))")
                try await manager.downloadAssetsIfNeeded(for: [module], generation: generation)
            }
        }
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
        try await prepareAssets(for: modules) { manager, generation in
            try await manager.downloadAssetsIfNeeded(for: modules, generation: generation)
        }
    }

    private func downloadAssetsIfNeeded(for modules: [any SpeechModule], generation: Int) async throws {
        try requireCurrent(generation)
        if let assetDownloader {
            try await assetDownloader(modules)
            return
        }
        let request = try await reservations.withInventoryAccess {
            try await self.requestInstallation(for: modules, generation: generation)
        }
        if let downloader = request {
            try requireCurrent(generation)
            currentDownloadProgress = downloader.progress
            logger.info("Starting asset download for \(modules.count) module(s)")
            do {
                try await downloader.downloadAndInstall()
            } catch {
                if self.generation == generation { currentDownloadProgress = nil }
                logger.error("Asset download failed: \(error.localizedDescription, privacy: .public)")

                // Check for network connectivity errors
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain,
                   nsError.code == URLError.notConnectedToInternet.rawValue {
                    throw SpeechSessionError.modelDownloadNoInternet
                }

                throw SpeechSessionError.modelDownloadFailed(nsError)
            }
            try requireCurrent(generation)
            currentDownloadProgress = nil
            logger.notice("Asset download completed successfully")
        } else {
            try requireCurrent(generation)
            currentDownloadProgress = nil
            logger.debug("No asset download required for modules")
        }
    }

    private func requestInstallation(
        for modules: [any SpeechModule], generation: Int
    ) async throws -> AssetInstallationRequest? {
        try requireCurrent(generation)
        return try await installationRequest(modules)
    }

    /// Retire pending preparation without waiting for a native download to finish.
    func releaseLocales() async {
        generation &+= 1
        let pending = leases
        leases.removeAll()
        currentDownloadProgress = nil
        for lease in pending { await reservations.release(lease) }
    }

    private func prepareAssets(
        for modules: [any SpeechModule],
        install: @Sendable (isolated ModelManager, Int) async throws -> Void
    ) async throws {
        let generation = self.generation
        try requireCurrent(generation)
        // Preserve first-install behavior: downloading may create native reservations.
        // Those reservations remain borrowed; only explicit acquisitions are owned here.
        try await install(self, generation)
        try requireCurrent(generation)
        var acquired: [SpeechAssetReservations.Lease] = []
        do {
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
                try requireCurrent(generation)
            }
            leases.formUnion(acquired)
        } catch {
            for lease in acquired { await reservations.release(lease) }
            throw error
        }
    }

    private func requireCurrent(_ generation: Int) throws {
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
    }
}
