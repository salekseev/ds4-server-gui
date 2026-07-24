import Foundation

// MARK: - Pure ds4-server argument construction (unit-tested; no side effects)

/// Snapshot of everything that influences the ds4-server command line.
struct ServerArgsConfig {
    var modelPath: String
    var ctxSize: Int
    var port: Int
    var host: String
    var enableDiskKV: Bool
    var kvDiskDir: String
    var kvDiskSpaceMB: Int
    var enableCORS: Bool
    var powerPercent: Int
    var enableSSDStreaming: Bool
    var ssdStreamingCacheGB: Int
    var threads: Int
    var prefillChunk: Int
    var enableDSpark: Bool
    var dsparkModelPath: String
    var dsparkConfidence: Double
    var defaultMaxTokens: Int
}

extension ServerArgsConfig {
    init(settings: Settings) {
        self.init(
            modelPath: settings.modelPath,
            ctxSize: settings.ctxSize,
            port: settings.port,
            host: settings.host,
            enableDiskKV: settings.enableDiskKV,
            kvDiskDir: settings.kvDiskDir,
            kvDiskSpaceMB: settings.kvDiskSpaceMB,
            enableCORS: settings.enableCORS,
            powerPercent: settings.powerPercent,
            enableSSDStreaming: settings.enableSSDStreaming,
            ssdStreamingCacheGB: settings.ssdStreamingCacheGB,
            threads: settings.threads,
            prefillChunk: settings.prefillChunk,
            enableDSpark: settings.enableDSpark,
            dsparkModelPath: settings.dsparkModelPath,
            dsparkConfidence: settings.dsparkConfidence,
            defaultMaxTokens: settings.defaultMaxTokens
        )
    }
}

/// KV cache dir with the documented default when unset.
/// Caller is responsible for creating this directory: the legacy
/// ServerManager.buildArgs did `mkdir` as a side effect; this pure function
/// intentionally does not.
func resolvedKVDiskDir(_ stored: String) -> String {
    stored.isEmpty
        ? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ds4/kvcache").path
        : stored
}

func buildServerArgs(config c: ServerArgsConfig,
                     metalParentDir: String) -> (args: [String], warnings: [String]) {
    var args = ["ds4-server"]
    var warnings: [String] = []
    args += ["--chdir", metalParentDir]
    args += ["-m", c.modelPath]
    args += ["--ctx", String(c.ctxSize)]
    args += ["--port", String(c.port)]
    if c.host != "127.0.0.1" && !c.host.isEmpty {
        args += ["--host", c.host]
    }
    if c.enableDiskKV {
        args += ["--kv-disk-dir", resolvedKVDiskDir(c.kvDiskDir)]
        args += ["--kv-disk-space-mb", String(c.kvDiskSpaceMB)]
    }
    if c.enableCORS { args += ["--cors"] }
    if c.powerPercent < 100 { args += ["--power", String(c.powerPercent)] }
    if c.enableSSDStreaming {
        args += ["--ssd-streaming"]
        if c.ssdStreamingCacheGB > 0 {
            args += ["--ssd-streaming-cache-experts", "\(c.ssdStreamingCacheGB)GB"]
        }
    }
    if c.threads > 0 { args += ["--threads", String(c.threads)] }
    if c.prefillChunk > 0 { args += ["--prefill-chunk", String(c.prefillChunk)] }
    if c.enableDSpark {
        if c.enableSSDStreaming {
            // Engine refuses --ssd-streaming with --mtp; SSD streaming wins because
            // dropping it could make the model not fit in memory.
            warnings.append("DSpark is incompatible with SSD streaming — starting without DSpark.")
        } else {
            args += ["--mtp", c.dsparkModelPath, "--dspark"]
            if c.dsparkConfidence != 0.9 {
                args += ["--dspark-confidence", String(c.dsparkConfidence)]
            }
        }
    }
    if c.defaultMaxTokens > 0 { args += ["--tokens", String(c.defaultMaxTokens)] }
    return (args, warnings)
}
