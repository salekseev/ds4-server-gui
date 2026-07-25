import Foundation

// MARK: - Security-scoped bookmark persistence
//
// The sandboxed app only keeps NSOpenPanel read grants for the process
// lifetime. Bookmarks make user-selected files (model, DSpark support
// file, custom KV dir) readable across relaunches.

enum BookmarkStore {

    static let modelKey  = "modelPathBookmark"
    static let dsparkKey = "dsparkModelPathBookmark"
    static let kvDirKey  = "kvDiskDirBookmark"

    private static let defaults =
        UserDefaults(suiteName: Settings.suiteName) ?? UserDefaults.standard

    /// URLs kept alive (access started) for the app's lifetime.
    private static var activeURLs: [String: URL] = [:]

    /// Save a security-scoped bookmark for a URL just granted via NSOpenPanel.
    static func save(url: URL, forKey key: String) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        defaults.set(data, forKey: key)
        _ = url.startAccessingSecurityScopedResource()
        activeURLs[key] = url
    }

    /// Drop a stored bookmark (e.g. the user cleared the path).
    static func clear(forKey key: String) {
        defaults.removeObject(forKey: key)
        activeURLs.removeValue(forKey: key)
    }

    /// Resolve and start accessing all stored bookmarks. Call once at launch,
    /// before the server first starts. Stale bookmarks are refreshed; broken
    /// ones are dropped (start()'s readability validation reports the problem).
    static func restoreAll() {
        for key in [modelKey, dsparkKey, kvDirKey] {
            guard let data = defaults.data(forKey: key) else { continue }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                defaults.removeObject(forKey: key)
                continue
            }
            _ = url.startAccessingSecurityScopedResource()
            activeURLs[key] = url
            if stale, let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(fresh, forKey: key)
            }
        }
    }
}
