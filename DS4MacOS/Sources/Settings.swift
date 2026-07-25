import Foundation

// MARK: - Settings (UserDefaults backed)

final class Settings {
    static let shared = Settings()
    private init() { migrateIfNeeded() }

    // Cannot use own Bundle ID as suite name (macOS restriction), append .prefs suffix
    static let suiteName = "DS4ServerAppPreferences"
    private let defaults = UserDefaults(suiteName: Settings.suiteName) ?? UserDefaults.standard

    private func migrateIfNeeded() {
        guard let newD = UserDefaults(suiteName: Settings.suiteName) else { return }
        let keys = ["modelPath", "port", "host", "ctxSize", "enableDiskKV",
                    "kvDiskDir", "kvDiskSpaceMB", "enableCORS", "noThink", "powerPercent"]
        // Migrate from UserDefaults.standard (old bundle ID suite is unsafe to access, read from standard)
        var migrated = false
        for key in keys {
            if let val = UserDefaults.standard.object(forKey: key),
               newD.object(forKey: key) == nil {
                newD.set(val, forKey: key)
                migrated = true
            }
        }
        // Fix incorrect default: ctxSize was mistakenly defaulted to 100000 instead
        // of 32768. One-shot: a user may legitimately choose 100000 later.
        if !newD.bool(forKey: "ctxSize100kResetDone") {
            if newD.integer(forKey: Key.ctxSize) == 100000 {
                newD.set(32768, forKey: Key.ctxSize)
                migrated = true
            }
            newD.set(true, forKey: "ctxSize100kResetDone")
        }
        if migrated { newD.synchronize() }
    }

    private enum Key {
        static let modelPath        = "modelPath"
        static let port             = "port"
        static let host             = "host"
        static let ctxSize          = "ctxSize"
        static let enableDiskKV     = "enableDiskKV"
        static let kvDiskDir        = "kvDiskDir"
        static let kvDiskSpaceMB    = "kvDiskSpaceMB"
        static let enableCORS       = "enableCORS"
        static let noThink          = "noThink"
        static let powerPercent     = "powerPercent"
        static let enableSSDStreaming   = "enableSSDStreaming"
        static let ssdStreamingCacheGB  = "ssdStreamingCacheGB"
        static let threads              = "threads"
        static let prefillChunk         = "prefillChunk"
        static let enableDSpark         = "enableDSpark"
        static let dsparkModelPath      = "dsparkModelPath"
        static let dsparkConfidence     = "dsparkConfidence"
        static let defaultMaxTokens     = "defaultMaxTokens"
    }

    var modelPath: String {
        get { defaults.string(forKey: Key.modelPath) ?? "" }
        set { defaults.set(newValue, forKey: Key.modelPath) }
    }


    var port: Int {
        get { let v = defaults.integer(forKey: Key.port); return v > 0 ? v : 8000 }
        set { defaults.set(newValue, forKey: Key.port) }
    }

    var host: String {
        get { let v = defaults.string(forKey: Key.host) ?? ""; return v.isEmpty ? "127.0.0.1" : v }
        set { defaults.set(newValue, forKey: Key.host) }
    }

    var ctxSize: Int {
        get { let v = defaults.integer(forKey: Key.ctxSize); return v > 0 ? v : 32768 }
        set { defaults.set(newValue, forKey: Key.ctxSize) }
    }

    var enableDiskKV: Bool {
        get { defaults.bool(forKey: Key.enableDiskKV) }
        set { defaults.set(newValue, forKey: Key.enableDiskKV) }
    }

    var kvDiskDir: String {
        get { defaults.string(forKey: Key.kvDiskDir) ?? "" }
        set { defaults.set(newValue, forKey: Key.kvDiskDir) }
    }

    var kvDiskSpaceMB: Int {
        get { let v = defaults.integer(forKey: Key.kvDiskSpaceMB); return v > 0 ? v : 8192 }
        set { defaults.set(newValue, forKey: Key.kvDiskSpaceMB) }
    }

    var enableCORS: Bool {
        get { defaults.bool(forKey: Key.enableCORS) }
        set { defaults.set(newValue, forKey: Key.enableCORS) }
    }

    var noThink: Bool {
        get { defaults.bool(forKey: Key.noThink) }
        set { defaults.set(newValue, forKey: Key.noThink) }
    }

    var powerPercent: Int {
        get { let v = defaults.integer(forKey: Key.powerPercent); return v > 0 ? v : 100 }
        set { defaults.set(min(100, max(1, newValue)), forKey: Key.powerPercent) }
    }

    // MARK: - Advanced / Performance

    /// Enable --ssd-streaming: stream expert weights from SSD on demand instead of full GPU residency.
    var enableSSDStreaming: Bool {
        get { defaults.bool(forKey: Key.enableSSDStreaming) }
        set { defaults.set(newValue, forKey: Key.enableSSDStreaming) }
    }

    /// SSD streaming expert cache size in GB. 0 = let engine decide (default: ~80% Metal working set).
    var ssdStreamingCacheGB: Int {
        get { defaults.integer(forKey: Key.ssdStreamingCacheGB) }
        set { defaults.set(max(0, newValue), forKey: Key.ssdStreamingCacheGB) }
    }

    /// CPU helper thread count. 0 = engine default.
    var threads: Int {
        get { defaults.integer(forKey: Key.threads) }
        set { defaults.set(max(0, newValue), forKey: Key.threads) }
    }

    /// Metal graph prefill chunk size. 0 = auto (4096 or 8192 depending on context).
    var prefillChunk: Int {
        get { defaults.integer(forKey: Key.prefillChunk) }
        set { defaults.set(max(0, newValue), forKey: Key.prefillChunk) }
    }

    // MARK: - DSpark speculative decoding

    /// Enable --dspark (requires dsparkModelPath; incompatible with SSD streaming).
    var enableDSpark: Bool {
        get { defaults.bool(forKey: Key.enableDSpark) }
        set { defaults.set(newValue, forKey: Key.enableDSpark) }
    }

    /// Draft/MTP support model file used by DSpark speculative decoding, passed via --mtp.
    var dsparkModelPath: String {
        get { defaults.string(forKey: Key.dsparkModelPath) ?? "" }
        set { defaults.set(newValue, forKey: Key.dsparkModelPath) }
    }

    /// --dspark-confidence threshold, clamped to 0...1. Unset reads as the
    /// engine default 0.9; an explicit 0 is preserved (engine diagnostics mode).
    var dsparkConfidence: Double {
        get {
            guard let v = defaults.object(forKey: Key.dsparkConfidence) as? Double else { return 0.9 }
            return min(1.0, max(0.0, v))
        }
        set { defaults.set(min(1.0, max(0.0, newValue)), forKey: Key.dsparkConfidence) }
    }

    /// --tokens: default max output tokens when clients omit a limit. 0 = engine default.
    var defaultMaxTokens: Int {
        get { max(0, defaults.integer(forKey: Key.defaultMaxTokens)) }
        set { defaults.set(max(0, newValue), forKey: Key.defaultMaxTokens) }
    }
}
