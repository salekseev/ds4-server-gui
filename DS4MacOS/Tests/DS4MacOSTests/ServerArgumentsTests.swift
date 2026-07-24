import XCTest
@testable import DS4MacOS

final class ServerArgumentsTests: XCTestCase {

    /// Baseline config ≈ the user's manual launch command.
    private func makeConfig() -> ServerArgsConfig {
        ServerArgsConfig(
            modelPath: "/m/ds4flash.gguf",
            ctxSize: 100000,
            port: 18888,
            host: "127.0.0.1",
            enableDiskKV: true,
            kvDiskDir: "/tmp/ds4-kv",
            kvDiskSpaceMB: 8192,
            enableCORS: false,
            powerPercent: 100,
            enableSSDStreaming: false,
            ssdStreamingCacheGB: 0,
            threads: 0,
            prefillChunk: 0,
            enableDSpark: false,
            dsparkModelPath: "",
            dsparkConfidence: 0.9,
            defaultMaxTokens: 0
        )
    }

    func testBaselineMatchesLegacyBuilder() {
        let (args, warnings) = buildServerArgs(config: makeConfig(), metalParentDir: "/METAL")
        XCTAssertEqual(args, [
            "ds4-server", "--chdir", "/METAL",
            "-m", "/m/ds4flash.gguf",
            "--ctx", "100000", "--port", "18888",
            "--kv-disk-dir", "/tmp/ds4-kv", "--kv-disk-space-mb", "8192",
        ])
        XCTAssertTrue(warnings.isEmpty)
    }

    func testDSparkEnabledAddsMtpAndDspark() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        let (args, warnings) = buildServerArgs(config: c, metalParentDir: "/METAL")
        XCTAssertTrue(args.contains("--dspark"))
        guard let i = args.firstIndex(of: "--mtp") else { return XCTFail("--mtp missing") }
        XCTAssertEqual(args[i + 1], "/m/dspark-support.gguf")
        XCTAssertFalse(args.contains("--dspark-confidence"), "default confidence must be elided")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testDSparkCustomConfidenceIncluded() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        c.dsparkConfidence = 0.7
        let (args, _) = buildServerArgs(config: c, metalParentDir: "/METAL")
        guard let i = args.firstIndex(of: "--dspark-confidence") else {
            return XCTFail("--dspark-confidence missing")
        }
        XCTAssertEqual(args[i + 1], "0.7")
    }

    func testDSparkZeroConfidencePreserved() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        c.dsparkConfidence = 0.0
        let (args, _) = buildServerArgs(config: c, metalParentDir: "/METAL")
        guard let i = args.firstIndex(of: "--dspark-confidence") else {
            return XCTFail("--dspark-confidence missing for explicit 0 (diagnostics mode)")
        }
        XCTAssertEqual(args[i + 1], "0.0")
    }

    func testDSparkDroppedWhenSSDStreamingEnabled() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        c.enableSSDStreaming = true
        let (args, warnings) = buildServerArgs(config: c, metalParentDir: "/METAL")
        XCTAssertFalse(args.contains("--dspark"))
        XCTAssertFalse(args.contains("--mtp"))
        XCTAssertTrue(args.contains("--ssd-streaming"))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("incompatible with SSD streaming"))
    }

    func testAllOptionsEnabled() {
        var c = makeConfig()
        c.host = "0.0.0.0"
        c.enableCORS = true
        c.powerPercent = 50
        c.enableSSDStreaming = true
        c.ssdStreamingCacheGB = 8
        c.threads = 8
        c.prefillChunk = 2048
        let (args, warnings) = buildServerArgs(config: c, metalParentDir: "/METAL")
        XCTAssertEqual(args, [
            "ds4-server", "--chdir", "/METAL",
            "-m", "/m/ds4flash.gguf",
            "--ctx", "100000", "--port", "18888",
            "--host", "0.0.0.0",
            "--kv-disk-dir", "/tmp/ds4-kv", "--kv-disk-space-mb", "8192",
            "--cors",
            "--power", "50",
            "--ssd-streaming", "--ssd-streaming-cache-experts", "8GB",
            "--threads", "8",
            "--prefill-chunk", "2048",
        ])
        XCTAssertTrue(warnings.isEmpty)
    }

    func testTokensIncludedWhenSet() {
        var c = makeConfig()
        c.defaultMaxTokens = 1500
        let (args, _) = buildServerArgs(config: c, metalParentDir: "/METAL")
        guard let i = args.firstIndex(of: "--tokens") else { return XCTFail("--tokens missing") }
        XCTAssertEqual(args[i + 1], "1500")
    }

    func testKVDirDefaultResolution() {
        XCTAssertEqual(resolvedKVDiskDir("/tmp/x"), "/tmp/x")
        XCTAssertTrue(resolvedKVDiskDir("").hasSuffix("/.ds4/kvcache"))
    }
}
