import Foundation

/// Reads and writes PendingShare data to the App Group shared container.
/// Compiled into both the main app target and the Share Extension target.
enum SharedContainerStore {
    static let appGroupID = "group.com.openminis.app"

    private static let pendingShareKey = "pendingShare"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Directory in the shared container for transferring attachment files.
    static var sharedFileDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("ShareExtension", isDirectory: true)
    }

    /// [T-sideload-appgroup-fallback] App Group container with a LOCAL fallback.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil when
    /// the app's signature does not carry the group entitlement — exactly the
    /// situation for a re-signed (sideloaded) build, because the signing
    /// profile cannot authorize `group.com.openminis.app`. Three call sites in
    /// the launch path force-unwrapped that result and crashed on the first
    /// view update (migrateSharedDirToAppGroup, `minisAppGroupRoot`,
    /// `minisConfigRoot`).
    ///
    /// Falling back to a private Library directory keeps the app fully usable
    /// in single-process mode. At runtime the container is only needed for
    /// cross-process sharing (FileProvider extension) and for stable paths
    /// across reinstalls — nothing *requires* the path to live inside the
    /// group container, so every consumer keeps working against the fallback.
    /// When the entitlement IS present (normal developer/App Store builds),
    /// this is byte-for-byte the previous behavior.
    static var containerURLWithFallback: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let url = lib.appendingPathComponent("MinisChat/AppGroupFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Write (called by Share Extension)

    static func savePendingShare(_ share: PendingShare) {
        guard let defaults = sharedDefaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(share) {
            defaults.set(data, forKey: pendingShareKey)
            defaults.synchronize()
        }
    }

    // MARK: - Read & Consume (called by main app)

    static func loadPendingShare() -> PendingShare? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: pendingShareKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingShare.self, from: data)
    }

    static func clearPendingShare() {
        sharedDefaults?.removeObject(forKey: pendingShareKey)
        sharedDefaults?.synchronize()
    }

    /// Remove all files from the shared transfer directory.
    static func cleanSharedFiles() {
        guard let dir = sharedFileDirectory else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }
}
