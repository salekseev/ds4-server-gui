import AppKit
import Foundation

// MARK: - Trigger reason

enum ModelSetupReason {
    case firstLaunch       // First launch, no model has been configured
    case modelNotFound     // Path is configured but file doesn't exist or is too small
    case loadError(String) // Server failed to load the model
}

// MARK: - ModelSetupWindowController

final class ModelSetupWindowController: NSWindowController, NSWindowDelegate {

    var onComplete: ((String?) -> Void)?

    private let reason: ModelSetupReason
    private var titleLabel: NSTextField!
    private var descLabel: NSTextField!
    private var reasonLabel: NSTextField!

    init(reason: ModelSetupReason = .firstLaunch) {
        self.reason = reason
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("setup.window.title")
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // Title
        titleLabel = NSTextField(labelWithString: L("setup.title"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 20, y: 172, width: 480, height: 24)
        cv.addSubview(titleLabel)

        // Reason description (different text depending on reason)
        let reasonText: String
        switch reason {
        case .firstLaunch:
            reasonText = L("setup.reason.first_launch")
        case .modelNotFound:
            reasonText = L("setup.reason.not_found", Settings.shared.modelPath)
        case .loadError(let msg):
            reasonText = L("setup.reason.load_error", msg)
        }

        reasonLabel = NSTextField(wrappingLabelWithString: reasonText)
        reasonLabel.frame = NSRect(x: 20, y: 120, width: 480, height: 46)
        reasonLabel.textColor = .secondaryLabelColor
        reasonLabel.font = NSFont.systemFont(ofSize: 12)
        cv.addSubview(reasonLabel)

        // Instruction label
        descLabel = NSTextField(labelWithString: L("setup.desc"))
        descLabel.frame = NSRect(x: 20, y: 96, width: 480, height: 18)
        descLabel.textColor = .secondaryLabelColor
        cv.addSubview(descLabel)

        // Cancel button
        let cancelButton = NSButton(title: L("setup.button.cancel"), target: self, action: #selector(cancelClicked))
        cancelButton.frame = NSRect(x: 20, y: 20, width: 80, height: 28)
        cv.addSubview(cancelButton)

        // Browse button (primary action)
        let browseButton = NSButton(title: L("setup.button.browse"), target: self, action: #selector(browseClicked))
        browseButton.frame = NSRect(x: 350, y: 20, width: 150, height: 28)
        browseButton.bezelStyle = .rounded
        browseButton.keyEquivalent = "\r"
        cv.addSubview(browseButton)
    }

    // MARK: - Actions

    @objc private func browseClicked() {
        let panel = NSOpenPanel()
        panel.title = L("setup.panel.select")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            BookmarkStore.save(url: url, forKey: BookmarkStore.modelKey)
            self?.finish(with: url.path)
        }
    }

    @objc private func cancelClicked() {
        onComplete?(nil)
        close()
    }

    // MARK: - Helpers

    private func finish(with path: String) {
        onComplete?(path)
        close()
    }

    // MARK: - Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onComplete?(nil)
        return true
    }
}
