import AppKit
import ServiceManagement

// MARK: - SettingsWindowController

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onApply: (() -> Void)?

    // Server tab
    private var modelPathField: NSTextField!
    private var portField: NSTextField!
    private var hostField: NSTextField!
    private var corsCheck: NSButton!
    private var launchAtLoginCheck: NSButton!

    // Performance tab
    private var ctxField: NSTextField!
    private var noThinkCheck: NSButton!
    private var powerSlider: NSSlider!
    private var powerLabel: NSTextField!
    private var ssdStreamingCheck: NSButton!
    private var ssdCacheField: NSTextField!
    private var threadsField: NSTextField!
    private var prefillChunkField: NSTextField!
    private var dsparkCheck: NSButton!
    private var dsparkPathField: NSTextField!
    private var dsparkConfidenceField: NSTextField!
    private var maxTokensField: NSTextField!

    // Storage tab
    private var diskKVCheck: NSButton!
    private var kvDirField: NSTextField!
    private var kvSizeField: NSTextField!

    private let W: CGFloat = 520

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.window.title")
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // ── Bottom buttons ────────────────────────────────────────────────
        let applyBtn = NSButton(title: L("settings.button.apply"),
                                target: self, action: #selector(applyClicked))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(applyBtn)

        let cancelBtn = NSButton(title: L("settings.button.cancel"),
                                 target: self, action: #selector(cancelClicked))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(cancelBtn)

        // ── Tab view ──────────────────────────────────────────────────────
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        cv.addSubview(tabView)

        let serverItem = NSTabViewItem(identifier: "server")
        serverItem.label = L("settings.tab.server")
        serverItem.view = buildServerTab()
        tabView.addTabViewItem(serverItem)

        let perfItem = NSTabViewItem(identifier: "performance")
        perfItem.label = L("settings.tab.performance")
        perfItem.view = buildPerformanceTab()
        tabView.addTabViewItem(perfItem)

        let storageItem = NSTabViewItem(identifier: "storage")
        storageItem.label = L("settings.tab.storage")
        storageItem.view = buildStorageTab()
        tabView.addTabViewItem(storageItem)

        // ── Auto Layout ───────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            applyBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            applyBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
            applyBtn.widthAnchor.constraint(equalToConstant: 110),

            cancelBtn.trailingAnchor.constraint(equalTo: applyBtn.leadingAnchor, constant: -8),
            cancelBtn.centerYAnchor.constraint(equalTo: applyBtn.centerYAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),

            tabView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: applyBtn.topAnchor, constant: -16),
        ])
    }

    // MARK: - Server Tab

    private func buildServerTab() -> NSView {
        let container = NSView()

        // Model group
        let modelBox = makeSection(title: L("settings.group.model"))
        let modelDesc = makeNote(L("settings.desc.model"))
        modelPathField = makeField(placeholder: L("settings.placeholder.model"))
        let browseBtn = NSButton(title: L("settings.button.browse"),
                                 target: self, action: #selector(browseModelClicked))
        browseBtn.bezelStyle = .rounded
        browseBtn.translatesAutoresizingMaskIntoConstraints = false

        let modelRow = NSStackView(views: [modelPathField, browseBtn])
        modelRow.orientation = .horizontal
        modelRow.spacing = 8
        modelRow.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        modelPathField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let modelStack = vstack([modelDesc, modelRow], spacing: 8)
        modelBox.contentView?.addSubview(modelStack)
        pin(modelStack, to: modelBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // Network group
        let netBox = makeSection(title: L("settings.group.network"))

        portField = makeField(placeholder: "8000")
        portField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([portField.widthAnchor.constraint(equalToConstant: 80)])

        hostField = makeField(placeholder: "127.0.0.1")
        hostField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([hostField.widthAnchor.constraint(equalToConstant: 140)])

        let portRow = formRow(label: L("settings.label.port"),
                              control: portField,
                              hint: L("settings.hint.port"))
        let hostRow = formRow(label: L("settings.label.host"),
                              control: hostField,
                              hint: L("settings.hint.host"))
        corsCheck = makeCheckbox(L("settings.checkbox.cors_short"))

        let netStack = vstack([portRow, hostRow, corsCheck], spacing: 10)
        netBox.contentView?.addSubview(netStack)
        pin(netStack, to: netBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // System group
        let sysBox = makeSection(title: L("settings.group.system"))
        launchAtLoginCheck = makeCheckbox(L("settings.checkbox.launch_at_login_short"))
        let supported = LaunchAtLoginManager.shared.isSupported
        launchAtLoginCheck.isEnabled = supported
        let loginHintText = supported
            ? L("settings.hint.launch_at_login")
            : L("settings.hint.launch_at_login_unsupported")
        let loginNote = makeNote(loginHintText)

        let sysStack = vstack([launchAtLoginCheck, loginNote], spacing: 4)
        sysBox.contentView?.addSubview(sysStack)
        pin(sysStack, to: sysBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // Compose
        let outer = vstack([modelBox, netBox, sysBox], spacing: 12)
        container.addSubview(outer)
        pin(outer, to: container, insets: NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))

        return container
    }

    // MARK: - Performance Tab

    private func buildPerformanceTab() -> NSView {
        let container = NSView()

        // Context group
        let ctxBox = makeSection(title: L("settings.group.context"))
        ctxField = makeField(placeholder: "32768")
        ctxField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([ctxField.widthAnchor.constraint(equalToConstant: 100)])

        let ctxRow = formRow(label: L("settings.label.ctx_short"),
                             control: ctxField,
                             hint: nil)
        let ctxNote = makeNote(L("settings.hint.ctx"))
        noThinkCheck = makeCheckbox(L("settings.checkbox.nothink_short"))

        maxTokensField = makeField(placeholder: "393216")
        maxTokensField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([maxTokensField.widthAnchor.constraint(equalToConstant: 100)])
        let tokensRow = formRow(label: L("settings.label.max_tokens"),
                                control: maxTokensField,
                                hint: L("settings.hint.max_tokens"))
        let ctxStack = vstack([ctxRow, ctxNote, tokensRow, noThinkCheck], spacing: 8)
        ctxBox.contentView?.addSubview(ctxStack)
        pin(ctxStack, to: ctxBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // GPU Power group
        let gpuBox = makeSection(title: L("settings.group.gpu"))
        let gpuNote = makeNote(L("settings.desc.power"))

        let sliderRow = NSStackView()
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8
        sliderRow.translatesAutoresizingMaskIntoConstraints = false

        powerSlider = NSSlider()
        powerSlider.minValue = 10; powerSlider.maxValue = 100
        powerSlider.target = self; powerSlider.action = #selector(powerChanged)
        powerSlider.translatesAutoresizingMaskIntoConstraints = false

        powerLabel = NSTextField(labelWithString: "100%")
        powerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        powerLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([powerLabel.widthAnchor.constraint(equalToConstant: 44)])

        sliderRow.addArrangedSubview(powerSlider)
        sliderRow.addArrangedSubview(powerLabel)

        let gpuStack = vstack([gpuNote, sliderRow], spacing: 8)
        gpuBox.contentView?.addSubview(gpuStack)
        pin(gpuStack, to: gpuBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // SSD Streaming group
        let ssdBox = makeSection(title: L("settings.group.ssd"))
        ssdStreamingCheck = makeCheckbox(L("settings.checkbox.ssd_short"))
        ssdStreamingCheck.target = self
        ssdStreamingCheck.action = #selector(ssdToggled)
        let ssdNote = makeNote(L("settings.desc.ssd"))

        ssdCacheField = makeField(placeholder: L("settings.placeholder.ssd_cache"))
        ssdCacheField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([ssdCacheField.widthAnchor.constraint(equalToConstant: 80)])
        let cacheRow = formRow(label: L("settings.label.ssd_cache_short"),
                               control: ssdCacheField,
                               hint: L("settings.hint.ssd_cache"))

        // Threads + Prefill on one row
        threadsField = makeField(placeholder: "auto")
        prefillChunkField = makeField(placeholder: "auto")
        threadsField.translatesAutoresizingMaskIntoConstraints = false
        prefillChunkField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            threadsField.widthAnchor.constraint(equalToConstant: 80),
            prefillChunkField.widthAnchor.constraint(equalToConstant: 80),
        ])
        let tLabel = makeCaption("Threads")
        let pLabel = makeCaption("Prefill chunk")
        let advRow = NSStackView(views: [tLabel, threadsField, spacer(16), pLabel, prefillChunkField])
        advRow.orientation = .horizontal
        advRow.spacing = 6
        advRow.translatesAutoresizingMaskIntoConstraints = false

        let ssdStack = vstack([ssdStreamingCheck, ssdNote, cacheRow, advRow], spacing: 8)
        ssdBox.contentView?.addSubview(ssdStack)
        pin(ssdStack, to: ssdBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // DSpark speculative decoding group
        let dsparkBox = makeSection(title: L("settings.group.dspark"))
        dsparkCheck = makeCheckbox(L("settings.checkbox.dspark"))
        dsparkCheck.target = self
        dsparkCheck.action = #selector(dsparkToggled)
        let dsparkNote = makeNote(L("settings.desc.dspark"))

        dsparkPathField = makeField(placeholder: L("settings.placeholder.dspark_model"))
        let dsparkBrowseBtn = NSButton(title: L("settings.button.browse"),
                                       target: self, action: #selector(browseDSparkClicked))
        dsparkBrowseBtn.bezelStyle = .rounded
        dsparkBrowseBtn.translatesAutoresizingMaskIntoConstraints = false
        dsparkBrowseBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        dsparkPathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let dsparkPathRow = NSStackView(views: [dsparkPathField, dsparkBrowseBtn])
        dsparkPathRow.orientation = .horizontal
        dsparkPathRow.spacing = 8
        dsparkPathRow.translatesAutoresizingMaskIntoConstraints = false
        let dsparkModelRow = formRow(label: L("settings.label.dspark_model"),
                                     control: dsparkPathRow,
                                     hint: nil)

        dsparkConfidenceField = makeField(placeholder: "0.9")
        dsparkConfidenceField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dsparkConfidenceField.widthAnchor.constraint(equalToConstant: 80)])
        let confidenceRow = formRow(label: L("settings.label.dspark_confidence"),
                                    control: dsparkConfidenceField,
                                    hint: L("settings.hint.dspark_confidence"))

        let dsparkStack = vstack([dsparkCheck, dsparkNote, dsparkModelRow, confidenceRow], spacing: 8)
        dsparkBox.contentView?.addSubview(dsparkStack)
        pin(dsparkStack, to: dsparkBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        let outer = vstack([ctxBox, gpuBox, ssdBox, dsparkBox], spacing: 12)
        container.addSubview(outer)
        pin(outer, to: container, insets: NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))

        return container
    }

    // MARK: - Storage Tab

    private func buildStorageTab() -> NSView {
        let container = NSView()

        let kvBox = makeSection(title: L("settings.group.kv"))
        diskKVCheck = makeCheckbox(L("settings.checkbox.disk_kv_short"))
        let kvNote = makeNote(L("settings.desc.kv"))

        kvDirField = makeField(placeholder: L("settings.placeholder.kv_dir"))
        let kvBrowseBtn = NSButton(title: L("settings.button.browse"),
                                   target: self, action: #selector(browseKVClicked))
        kvBrowseBtn.bezelStyle = .rounded
        kvBrowseBtn.translatesAutoresizingMaskIntoConstraints = false
        kvBrowseBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        kvDirField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let dirRow = NSStackView(views: [kvDirField, kvBrowseBtn])
        dirRow.orientation = .horizontal
        dirRow.spacing = 8
        dirRow.translatesAutoresizingMaskIntoConstraints = false
        let dirFormRow = formRow(label: L("settings.label.kv_cache"),
                                 control: dirRow,
                                 hint: nil)

        kvSizeField = makeField(placeholder: "8192")
        kvSizeField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([kvSizeField.widthAnchor.constraint(equalToConstant: 90)])
        let sizeRow = formRow(label: L("settings.label.kv_size_short"),
                              control: kvSizeField,
                              hint: L("settings.hint.kv_size"))
        let pathNote = makeNote(L("settings.hint.kv_path"))

        let kvStack = vstack([diskKVCheck, kvNote, dirFormRow, sizeRow, pathNote], spacing: 8)
        kvBox.contentView?.addSubview(kvStack)
        pin(kvStack, to: kvBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        // Info box
        let infoBox = makeSection(title: L("settings.group.info"))
        let infoText = makeNote(L("settings.info.kv"))
        infoText.maximumNumberOfLines = 0
        infoBox.contentView?.addSubview(infoText)
        pin(infoText, to: infoBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        let outer = vstack([kvBox, infoBox], spacing: 12)
        container.addSubview(outer)
        pin(outer, to: container, insets: NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))

        return container
    }

    // MARK: - Layout Helpers

    private func vstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        // Make each arranged subview fill the full width
        for v in views {
            s.addConstraint(NSLayoutConstraint(
                item: v, attribute: .width, relatedBy: .equal,
                toItem: s, attribute: .width, multiplier: 1, constant: 0))
        }
        return s
    }

    private func makeSection(title: String) -> NSBox {
        let b = NSBox()
        b.title = title
        b.titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.bezelStyle = .roundedBezel
        f.cell?.wraps = false
        f.cell?.isScrollable = true
        f.usesSingleLineMode = true
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    private func makeCheckbox(_ title: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeNote(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return l
    }

    /// label | control  hint
    private func formRow(label labelText: String, control: NSView, hint: String?) -> NSStackView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        NSLayoutConstraint.activate([lbl.widthAnchor.constraint(equalToConstant: 160)])

        var arranged: [NSView] = [lbl, control]
        if let hintText = hint {
            let h = makeCaption(hintText)
            h.setContentHuggingPriority(.defaultLow, for: .horizontal)
            arranged.append(h)
        }
        let row = NSStackView(views: arranged)
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func spacer(_ w: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: w)])
        return v
    }

    private func pin(_ child: NSView, to parent: NSView,
                     insets i: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: i.top),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: i.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -i.right),
            child.bottomAnchor.constraint(lessThanOrEqualTo: parent.bottomAnchor, constant: -i.bottom),
        ])
    }

    // MARK: - Load / Save

    private func loadValues() {
        let s = Settings.shared
        modelPathField.stringValue    = s.modelPath
        portField.stringValue         = String(s.port)
        hostField.stringValue         = s.host
        corsCheck.state               = s.enableCORS ? .on : .off
        launchAtLoginCheck.state      = (SMAppService.mainApp.status == .enabled) ? .on : .off
        ctxField.stringValue          = String(s.ctxSize)
        noThinkCheck.state            = s.noThink ? .on : .off
        powerSlider.doubleValue       = Double(s.powerPercent)
        powerLabel.stringValue        = "\(s.powerPercent)%"
        ssdStreamingCheck.state       = s.enableSSDStreaming ? .on : .off
        ssdCacheField.stringValue     = s.ssdStreamingCacheGB > 0 ? String(s.ssdStreamingCacheGB) : ""
        threadsField.stringValue      = s.threads > 0 ? String(s.threads) : ""
        prefillChunkField.stringValue = s.prefillChunk > 0 ? String(s.prefillChunk) : ""
        dsparkCheck.state             = s.enableDSpark ? .on : .off
        dsparkPathField.stringValue   = s.dsparkModelPath
        dsparkConfidenceField.stringValue = s.dsparkConfidence == 0.9 ? "" : String(s.dsparkConfidence)
        maxTokensField.stringValue    = s.defaultMaxTokens > 0 ? String(s.defaultMaxTokens) : ""
        if ssdStreamingCheck.state == .on && dsparkCheck.state == .on {
            dsparkCheck.state = .off   // SSD streaming wins; matches buildServerArgs precedence
        }
        diskKVCheck.state             = s.enableDiskKV ? .on : .off
        kvDirField.stringValue        = s.kvDiskDir
        kvSizeField.stringValue       = String(s.kvDiskSpaceMB)
    }

    private func saveValues() {
        let s = Settings.shared
        s.modelPath           = modelPathField.stringValue.trimmingCharacters(in: .whitespaces)
        s.port                = Int(portField.stringValue) ?? 8000
        s.host                = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        s.enableCORS          = corsCheck.state == .on
        s.ctxSize             = Int(ctxField.stringValue) ?? 32768
        s.noThink             = noThinkCheck.state == .on
        s.powerPercent        = Int(powerSlider.doubleValue)
        s.enableSSDStreaming   = ssdStreamingCheck.state == .on
        s.ssdStreamingCacheGB = Int(ssdCacheField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        s.threads             = Int(threadsField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        s.prefillChunk        = Int(prefillChunkField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        s.enableDSpark        = dsparkCheck.state == .on
        s.dsparkModelPath     = dsparkPathField.stringValue.trimmingCharacters(in: .whitespaces)
        s.dsparkConfidence    = Double(dsparkConfidenceField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0.9
        s.defaultMaxTokens    = Int(maxTokensField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        s.enableDiskKV        = diskKVCheck.state == .on
        s.kvDiskDir           = kvDirField.stringValue.trimmingCharacters(in: .whitespaces)
        s.kvDiskSpaceMB       = Int(kvSizeField.stringValue) ?? 8192
        LaunchAtLoginManager.shared.setEnabled(launchAtLoginCheck.state == .on)
    }

    // MARK: - Actions

    @objc private func browseModelClicked() {
        let panel = NSOpenPanel()
        panel.title = L("settings.panel.model")
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        modelPathField.stringValue = url.path
    }

    @objc private func browseKVClicked() {
        let panel = NSOpenPanel()
        panel.title = L("settings.panel.kv_dir")
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        kvDirField.stringValue = url.path
    }

    @objc private func browseDSparkClicked() {
        let panel = NSOpenPanel()
        panel.title = L("settings.panel.dspark_model")
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dsparkPathField.stringValue = url.path
    }

    // DSpark and SSD streaming are mutually exclusive (engine refuses --mtp + --ssd-streaming)
    @objc private func dsparkToggled() {
        if dsparkCheck.state == .on { ssdStreamingCheck.state = .off }
    }

    @objc private func ssdToggled() {
        if ssdStreamingCheck.state == .on { dsparkCheck.state = .off }
    }

    @objc private func powerChanged() {
        powerLabel.stringValue = "\(Int(powerSlider.doubleValue))%"
    }

    @objc private func applyClicked() { saveValues(); close(); onApply?() }
    @objc private func cancelClicked() { close() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}
