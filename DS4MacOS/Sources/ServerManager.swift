import Foundation
#if canImport(ds4engine)
import ds4engine
#endif

// MARK: - Server Status

enum ServerStatus {
    case stopped
    case starting
    case running
    case error(String)
}

// MARK: - ServerManager

class ServerManager {

    var onStatusChange: (() -> Void)?
    /// Triggered when model file is invalid or server exit indicates load failure. Passes the corresponding ModelSetupReason.
    var onModelError: ((ModelSetupReason) -> Void)?

    private(set) var status: ServerStatus = .stopped {
        didSet { onStatusChange?() }
    }

    private var serverThread: Thread?
    private var isRunning = false
    private var logPipe: [Int32] = [-1, -1]
    private var origStdout: Int32 = -1
    private var origStderr: Int32 = -1
    private var logReadSource: DispatchSourceRead?

    // MARK: - Public API

    func start() {
        switch status {
        case .stopped, .error: break
        default: return
        }

        // A previous run may still be draining. Starting now would be unsafe:
        // ds4_server_reset_stop() below would un-stop it, and two engine
        // instances would share process-global state.
        if let old = serverThread, !old.isFinished {
            LogWindowController.shared.append("[WARN] Previous server instance is still shutting down; retry in a moment.\n")
            return
        }

        let settings = Settings.shared
        let path = settings.modelPath
        // Metadata (stat) succeeds under the sandbox even when actual read access
        // has been denied (e.g. a security-scoped bookmark that failed to resolve).
        // The in-process engine's open() would then be denied and upstream's
        // die() calls exit(1), killing the whole app with no chance to intercept
        // it — so we must prove data readability up front, not just existence.
        guard Self.readableFileSize(atPath: path) > 1_048_576 else {
            let msg = L("server.error.model_invalid", path)
            status = .error(msg)
            LogWindowController.shared.append("[ERROR] \(msg)\n")
            let reason: ModelSetupReason = path.isEmpty ? .firstLaunch : .modelNotFound
            onModelError?(reason)
            return
        }

        guard let metalDir = metalShadersDir() else {
            let msg = L("server.error.metal_missing")
            status = .error(msg)
            LogWindowController.shared.append("[ERROR] Metal shaders not found, please rebuild.\n")
            return
        }

        // DSpark support file must be valid when it will actually be used
        // (SSD streaming disables DSpark — see buildServerArgs).
        if settings.enableDSpark && !settings.enableSSDStreaming {
            let dsparkPath = settings.dsparkModelPath
            if Self.readableFileSize(atPath: dsparkPath) <= 1_048_576 {
                let msg = L("server.error.dspark_invalid", dsparkPath)
                status = .error(msg)
                LogWindowController.shared.append("[ERROR] \(msg)\n")
                return
            }
        }

        status = .starting
        isRunning = true

        // Set lock file path to a sandbox-allowed temp directory
        let lockFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ds4.lock").path
        setenv("DS4_LOCK_FILE", lockFile, 1)

        let config = ServerArgsConfig(settings: settings)
        if config.enableDiskKV {
            try? FileManager.default.createDirectory(
                atPath: resolvedKVDiskDir(config.kvDiskDir),
                withIntermediateDirectories: true)
        }
        let (args, warnings) = buildServerArgs(config: config, metalParentDir: metalDir)
        for w in warnings { LogWindowController.shared.append("[WARN] \(w)\n") }
        LogWindowController.shared.append("[INFO] Starting ds4-server (in-process)\n[INFO] chdir=\(metalDir)\n[INFO] args: \(args.dropFirst().joined(separator: " "))\n")

        setupLogCapture()

        // DEBUG: do not hijack stdout/stderr in Xcode debug environment, let output go directly to console
        #if DEBUG
        let isXcodeDebug = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
            || ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]?.hasPrefix("application.") == true
        if isXcodeDebug {
            teardownLogCapture()
        }
        #endif

        // Clear the stop flag a previous run's shutdown left behind; without
        // this, every engine run after the first drains and exits immediately.
        // Safe here: the guard above proved no previous run is still alive.
        ds4_server_reset_stop()

        let thread = Thread {
            let cArgs = args.map { strdup($0) }
            defer { cArgs.forEach { free($0) } }
            var argv: [UnsafeMutablePointer<CChar>?] = cArgs + [nil]

            let exitCode = argv.withUnsafeMutableBufferPointer { buf in
                ds4_server_main(Int32(args.count), buf.baseAddress)
            }

            self.teardownLogCapture()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.serverThread = nil
                self.isRunning = false
                LogWindowController.shared.append("[INFO] ds4_server_main exited (code=\(exitCode))\n")
                switch self.status {
                case .running:
                    self.status = .error(L("server.error.unexpected_exit", exitCode))
                case .starting:
                    let msg = L("server.error.start_failed", exitCode)
                    self.status = .error(msg)
                    // Exit during startup usually means model load failed; prompt user to re-select model
                    self.onModelError?(.loadError(msg))
                default:
                    break
                }
            }
        }
        thread.name = "ds4-server"
        thread.qualityOfService = QualityOfService.userInitiated
        serverThread = thread

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.isRunning else { return }
            if case .starting = self.status { self.status = .running }
        }

        thread.start()
    }

    func stop() {
        // Keep serverThread: start() uses it to detect a still-draining run.
        // The thread's exit handler clears it.
        isRunning = false
        ds4_server_request_stop()
        status = .stopped
        LogWindowController.shared.append("[INFO] Server stopped.\n")
    }

    func restart() {
        let oldThread = serverThread
        isRunning = false
        ds4_server_request_stop()
        status = .stopped
        LogWindowController.shared.append("[INFO] Restarting server...\n")

        DispatchQueue.global().async { [weak self] in
            // Wait for the previous engine run to fully exit; overlapping runs
            // share process-global engine state and must never coexist.
            var waited = 0
            while let t = oldThread, !t.isFinished, waited < 600 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 1
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let t = oldThread, !t.isFinished {
                    let msg = "Previous server instance did not shut down within 60s; not restarting."
                    self.status = .error(msg)
                    LogWindowController.shared.append("[ERROR] \(msg)\n")
                    return
                }
                self.start()
            }
        }
    }

    // MARK: - Readability Validation

    /// Opens the file for reading and seeks to the end to obtain its size.
    /// Unlike stat/metadata (FileManager.attributesOfItem, fileExists), this
    /// actually exercises file-read-data access, which is what the sandbox
    /// gates and what the in-process engine needs when it later open()s the
    /// path. Returns -1 if the path is empty or cannot be opened for reading.
    private static func readableFileSize(atPath path: String) -> Int64 {
        guard !path.isEmpty, let fh = FileHandle(forReadingAtPath: path) else { return -1 }
        defer { try? fh.close() }
        return Int64((try? fh.seekToEnd()) ?? 0)
    }

    // MARK: - Metal Shaders Directory

    private func metalShadersDir() -> String? {
        let fm = FileManager.default

        // 1. Xcode app bundle: Contents/Resources/metal/flash_attn.metal
        if let resourcesURL = Bundle.main.resourceURL {
            let check = resourcesURL.appendingPathComponent("metal/flash_attn.metal").path
            if fm.fileExists(atPath: check) {
                return resourcesURL.path
            }
        }

        // 2. SPM debug build: DS4MacOS_ds4engine.bundle next to the executable
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: "/")
        var cur = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            let bundleURL = cur.appendingPathComponent("DS4MacOS_ds4engine.bundle")
            let check = bundleURL.appendingPathComponent("metal/flash_attn.metal").path
            if fm.fileExists(atPath: check) {
                return bundleURL.path
            }
            cur = cur.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - Log Capture

    private func setupLogCapture() {
        var p = [Int32](repeating: -1, count: 2)
        guard pipe(&p) == 0 else { return }
        logPipe = p

        origStdout = dup(STDOUT_FILENO)
        origStderr = dup(STDERR_FILENO)
        dup2(p[1], STDOUT_FILENO)
        dup2(p[1], STDERR_FILENO)
        close(p[1])

        let src = DispatchSource.makeReadSource(fileDescriptor: p[0], queue: .global())
        src.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(p[0], &buf, buf.count - 1)
            guard n > 0, let text = String(bytes: buf.prefix(n), encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                LogWindowController.shared.append(text)
                if case .starting = self?.status {
                    let lower = text.lowercased()
                    if ["listening", "ready", "port ", "accepting"].contains(where: { lower.contains($0) }) {
                        self?.status = .running
                    }
                }
            }
        }
        src.resume()
        logReadSource = src
    }

    private func teardownLogCapture() {
        logReadSource?.cancel()
        logReadSource = nil
        if origStdout >= 0 { dup2(origStdout, STDOUT_FILENO); close(origStdout); origStdout = -1 }
        if origStderr >= 0 { dup2(origStderr, STDERR_FILENO); close(origStderr); origStderr = -1 }
        if logPipe[0] >= 0 { close(logPipe[0]); logPipe[0] = -1 }
    }
}
