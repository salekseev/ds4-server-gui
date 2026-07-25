import AppKit
import Foundation

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarItem: NSStatusItem?
    private var serverManager: ServerManager!
    private var settingsWindowController: SettingsWindowController?
    private var modelSetupWindowController: ModelSetupWindowController?
    private var userDidRequestQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setup()
    }

    func setup() {
        guard serverManager == nil else { return }
        // Must run before the server auto-starts: restores security-scoped
        // access to previously user-selected model/DSpark/KV paths, which the
        // sandbox otherwise revokes when NSOpenPanel's process-lifetime grant
        // expires across relaunches.
        BookmarkStore.restoreAll()
        serverManager = ServerManager()
        serverManager.onStatusChange = { [weak self] in
            DispatchQueue.main.async { self?.updateMenuIcon() }
        }
        serverManager.onModelError = { [weak self] reason in
            DispatchQueue.main.async { self?.showModelSetupWindow(reason: reason) }
        }
        setupStatusItem()
        checkModelAndStart()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return userDidRequestQuit ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverManager?.stop()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuIcon()
    }

    private func updateMenuIcon() {
        guard let button = statusBarItem?.button else { return }
        switch serverManager.status {
        case .stopped:
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "DS4 Stopped")
            button.image?.isTemplate = true
        case .starting:
            button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "DS4 Starting")
            button.image?.isTemplate = true
        case .running:
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "DS4 Running")
            button.image?.isTemplate = true
        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "DS4 Error")
            button.image?.isTemplate = true
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: L("menu.title"), action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusText: String
        switch serverManager.status {
        case .stopped:
            statusText = L("menu.status.stopped")
        case .starting:
            statusText = L("menu.status.starting")
        case .running:
            statusText = L("menu.status.running", Settings.shared.port)
        case .error(let msg):
            statusText = L("menu.status.error", String(msg.prefix(50)))
        }
        let stItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        stItem.isEnabled = false
        menu.addItem(stItem)

        menu.addItem(.separator())

        switch serverManager.status {
        case .stopped, .error:
            let startItem = NSMenuItem(title: L("menu.start"), action: #selector(startServer), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)
        case .starting:
            let item = NSMenuItem(title: L("menu.starting"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .running:
            let stopItem = NSMenuItem(title: L("menu.stop"), action: #selector(stopServer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            let restartItem = NSMenuItem(title: L("menu.restart"), action: #selector(restartServer), keyEquivalent: "")
            restartItem.target = self
            menu.addItem(restartItem)
        }

        if case .running = serverManager.status {
            menu.addItem(.separator())
            let urlItem = NSMenuItem(
                title: L("menu.copy_url", Settings.shared.port),
                action: #selector(copyAPIURL),
                keyEquivalent: ""
            )
            urlItem.target = self
            menu.addItem(urlItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let logsItem = NSMenuItem(title: L("menu.logs"), action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarItem?.menu = menu
    }

    // MARK: - Model Check & Start

    private func checkModelAndStart() {
        let path = Settings.shared.modelPath
        if path.isEmpty {
            showModelSetupWindow(reason: .firstLaunch)
            return
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 ?? 0) ?? 0
        let exists = FileManager.default.fileExists(atPath: path)
        if !exists || fileSize <= 1_048_576 {
            showModelSetupWindow(reason: .modelNotFound)
            return
        }
        serverManager.start()
    }

    func showModelSetupWindow(reason: ModelSetupReason = .firstLaunch) {
        // Don't show duplicate setup window if one is already visible
        if let existing = modelSetupWindowController, existing.window?.isVisible == true {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        modelSetupWindowController = ModelSetupWindowController(reason: reason)
        modelSetupWindowController?.onComplete = { [weak self] modelPath in
            DispatchQueue.main.async {
                self?.modelSetupWindowController = nil
                if let path = modelPath {
                    Settings.shared.modelPath = path
                    self?.serverManager.start()
                }
            }
        }
        modelSetupWindowController?.showWindow(nil)
        modelSetupWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu Actions

    @objc private func quitApp() {
        userDidRequestQuit = true
        serverManager?.stop()
        NSApp.terminate(nil)
    }

    @objc private func startServer() {
        let path = Settings.shared.modelPath
        if path.isEmpty {
            showModelSetupWindow(reason: .firstLaunch)
            return
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 ?? 0) ?? 0
        let exists = FileManager.default.fileExists(atPath: path)
        if !exists || fileSize <= 1_048_576 {
            showModelSetupWindow(reason: .modelNotFound)
            return
        }
        serverManager.start()
    }

    @objc private func stopServer() {
        serverManager.stop()
    }

    @objc private func restartServer() {
        serverManager.restart()
    }

    private var copyFeedbackTimer: Timer?

    @objc private func copyAPIURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://127.0.0.1:\(Settings.shared.port)", forType: .string)

        // Show brief "✓ Copied!" feedback in the menu item
        copyFeedbackTimer?.invalidate()
        if let menu = statusBarItem?.menu,
           let item = menu.items.first(where: { $0.action == #selector(copyAPIURL) }) {
            item.title = L("menu.copied")
            copyFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                item.title = L("menu.copy_url", Settings.shared.port)
                self?.copyFeedbackTimer = nil
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.onApply = { [weak self] in
            DispatchQueue.main.async {
                switch self?.serverManager.status {
                case .running:
                    self?.serverManager.restart()
                case .error:
                    // Settings changes are the usual remedy for a failed start
                    // (e.g. bad DSpark support path) — retry immediately.
                    self?.serverManager.start()
                default:
                    break
                }
            }
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openLogs() {
        LogWindowController.shared.showWindow(nil)
        LogWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }
}
