import AppKit

private enum SettingsSection: Int, CaseIterable {
    case shortcuts
    case scrolling
    case cursorControl
    case halo
    case autoClicker

    var title: String {
        switch self {
        case .shortcuts:
            return "Shortcuts"
        case .scrolling:
            return "Scrolling"
        case .cursorControl:
            return "Cursor Control"
        case .halo:
            return "Halo Settings"
        case .autoClicker:
            return "Auto Clicker"
        }
    }
}

private enum ScrollSettingKey {
    case pixelDelta
    case eventsPerShortcut
    case accelerationPerRepeat
    case maximumAccelerationMultiplier
    case verticalMultiplier
    case horizontalMultiplier
}

private enum AutoClickerSettingKey {
    case clicksPerSecond
}

private enum CursorSettingKey {
    case initialSpeed
    case maximumSpeed
    case accelerationPerFrame
    case frameRate
    case haloSize
    case haloOpacity
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class NumericSettingControl: NSObject, NSTextFieldDelegate {
    let slider: NSSlider
    let field: NSTextField
    let isInteger: Bool
    let suffix: String
    private let minimum: Double
    private let maximum: Double

    init(
        minimum: Double,
        maximum: Double,
        isInteger: Bool,
        suffix: String,
        target: AnyObject,
        action: Selector
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.isInteger = isInteger
        self.suffix = suffix

        slider = NSSlider(
            value: minimum,
            minValue: minimum,
            maxValue: maximum,
            target: target,
            action: action
        )
        slider.widthAnchor.constraint(equalToConstant: 190).isActive = true

        field = NSTextField(string: "")
        field.target = target
        field.action = action
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 86).isActive = true

        super.init()
        field.delegate = self
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Apply value immediately
            if let target = field.target, let action = field.action {
                NSApp.sendAction(action, to: target, from: field)
            }
            // Remove focus
            field.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func row(title: String, description: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.maximumNumberOfLines = 1

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2

        let labelStack = NSStackView(views: [titleLabel, descriptionLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.edgeInsets = NSEdgeInsets(top: 1, left: 0, bottom: 1, right: 0)
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

        let suffixLabel = NSTextField(labelWithString: suffix)
        suffixLabel.textColor = .secondaryLabelColor
        suffixLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let row = NSStackView(views: [labelStack, slider, field, suffixLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        return row
    }

    func setValue(_ value: Double) {
        let clamped = clamped(value)
        slider.doubleValue = clamped
        field.stringValue = formatted(clamped)
    }

    func value(sender: Any?) -> Double {
        if let sender = sender as? NSSlider, sender === slider {
            return normalized(slider.doubleValue)
        }

        if let sender = sender as? NSTextField, sender === field {
            return normalized(field.doubleValue)
        }

        return normalized(field.doubleValue)
    }

    private func normalized(_ value: Double) -> Double {
        let clamped = clamped(value)
        return isInteger ? clamped.rounded() : clamped
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    private func formatted(_ value: Double) -> String {
        if isInteger {
            return "\(Int(value.rounded()))"
        }

        return String(format: "%.2f", value)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let autoClickerSettingsProvider: () -> AutoClickerSettings
    private let onAutoClickerSettingsChange: (AutoClickerSettings) -> Void
    private let onRestoreAutoClickerSettingsDefaults: () -> AutoClickerSettings
    private let modeOptionsProvider: () -> CursorModeOptions
    private let onModeOptionsChange: (CursorModeOptions) -> Void
    private var separateExitCheckbox: NSButton?
    private let onToggleCursorMode: () -> Bool
    private var entryModeButton: NSButton?
    private var entryStatusLabel: NSTextField?
    private var exitShortcutRow: NSView?
    private let shortcutProvider: (ShortcutIdentifier) -> KeyboardShortcut
    private let scrollSettingsProvider: () -> ScrollSettings
    private let cursorSettingsProvider: () -> CursorSettings
    private let cursorMovementBindingProvider: (CursorMovementDirection) -> KeyboardShortcut
    private let onShortcutChange: (ShortcutIdentifier, KeyboardShortcut) -> ShortcutUpdateResult
    private let onRestoreDefaults: () -> ShortcutUpdateResult
    private let onScrollSettingsChange: (ScrollSettings) -> Void
    private let onRestoreScrollSettingsDefaults: () -> ScrollSettings
    private let onCursorSettingsChange: (CursorSettings) -> Void
    private let onRestoreCursorSettingsDefaults: () -> CursorSettings
    private let onCursorMovementBindingChange: (
        CursorMovementDirection,
        KeyboardShortcut
    ) -> Result<CursorMovementBindings, CursorMovementBindingValidationError>
    private let onRestoreCursorMovementBindingsDefaults: () -> CursorMovementBindings
    private let onRecordingStateChanged: (Bool) -> Void
    private var shortcutButtons: [ShortcutIdentifier: ShortcutRecorderButton] = [:]
    private var cursorMovementButtons: [CursorMovementDirection: ShortcutRecorderButton] = [:]
    private var scrollControls: [ScrollSettingKey: NumericSettingControl] = [:]
    private var cursorControls: [CursorSettingKey: NumericSettingControl] = [:]
    private var autoClickerControls: [AutoClickerSettingKey: NumericSettingControl] = [:]
    private var recordingEventMonitor: Any?
    private var haloColorButtons: [HaloColor: ColorButton] = [:]
    private let messageLabel = NSTextField(labelWithString: "")
    private let tabView = NSTabView()

    init(
        autoClickerSettingsProvider: @escaping () -> AutoClickerSettings,
        onAutoClickerSettingsChange: @escaping (AutoClickerSettings) -> Void,
        onRestoreAutoClickerSettingsDefaults: @escaping () -> AutoClickerSettings,
        onToggleCursorMode: @escaping () -> Bool,
        modeOptionsProvider: @escaping () -> CursorModeOptions,
        onModeOptionsChange: @escaping (CursorModeOptions) -> Void,
        shortcutProvider: @escaping (ShortcutIdentifier) -> KeyboardShortcut,
        scrollSettingsProvider: @escaping () -> ScrollSettings,
        cursorSettingsProvider: @escaping () -> CursorSettings,
        cursorMovementBindingProvider: @escaping (CursorMovementDirection) -> KeyboardShortcut,
        onShortcutChange: @escaping (ShortcutIdentifier, KeyboardShortcut) -> ShortcutUpdateResult,
        onRestoreDefaults: @escaping () -> ShortcutUpdateResult,
        onScrollSettingsChange: @escaping (ScrollSettings) -> Void,
        onRestoreScrollSettingsDefaults: @escaping () -> ScrollSettings,
        onCursorSettingsChange: @escaping (CursorSettings) -> Void,
        onRestoreCursorSettingsDefaults: @escaping () -> CursorSettings,
        onCursorMovementBindingChange: @escaping (
            CursorMovementDirection,
            KeyboardShortcut
        ) -> Result<CursorMovementBindings, CursorMovementBindingValidationError>,
        onRestoreCursorMovementBindingsDefaults: @escaping () -> CursorMovementBindings,
        onRecordingStateChanged: @escaping (Bool) -> Void
    ) {
        self.autoClickerSettingsProvider = autoClickerSettingsProvider
        self.onAutoClickerSettingsChange = onAutoClickerSettingsChange
        self.onRestoreAutoClickerSettingsDefaults = onRestoreAutoClickerSettingsDefaults
        self.onToggleCursorMode = onToggleCursorMode
        self.modeOptionsProvider = modeOptionsProvider
        self.onModeOptionsChange = onModeOptionsChange
        self.shortcutProvider = shortcutProvider
        self.scrollSettingsProvider = scrollSettingsProvider
        self.cursorSettingsProvider = cursorSettingsProvider
        self.cursorMovementBindingProvider = cursorMovementBindingProvider
        self.onShortcutChange = onShortcutChange
        self.onRestoreDefaults = onRestoreDefaults
        self.onScrollSettingsChange = onScrollSettingsChange
        self.onRestoreScrollSettingsDefaults = onRestoreScrollSettingsDefaults
        self.onCursorSettingsChange = onCursorSettingsChange
        self.onRestoreCursorSettingsDefaults = onRestoreCursorSettingsDefaults
        self.onCursorMovementBindingChange = onCursorMovementBindingChange
        self.onRestoreCursorMovementBindingsDefaults = onRestoreCursorMovementBindingsDefaults
        self.onRecordingStateChanged = onRecordingStateChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 940),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else { return }

        refreshModeOptions()
        refreshShortcutButtons()
        refreshScrollSettingsControls()
        refreshCursorSettingsControls()
        refreshAutoClickerSettingsControls()
        refreshCursorMovementButtons()
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = "Cursor Control Settings"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        window.contentView = makeContentView()
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func makeContentView() -> NSView {
        let container = NSView()

        let titleLabel = NSTextField(labelWithString: "Cursor Control Settings")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)

        let detailLabel = NSTextField(
            wrappingLabelWithString: "Enter cursor mode to use your keyboard as a mouse. Exit to type normally."
        )
        detailLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 0

        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0

        configureTabView()
        let entrySection = makeEntrySection()

        let restoreButton = NSButton(
            title: "Restore All Defaults",
            target: self,
            action: #selector(restoreDefaults)
        )
        restoreButton.bezelStyle = .rounded

        let stack = NSStackView(
            views: [
                titleLabel,
                detailLabel,
                entrySection,
                tabView,
                messageLabel,
                restoreButton
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        tabView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            entrySection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tabView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        refreshModeOptions()
        refreshShortcutButtons()
        refreshScrollSettingsControls()
        refreshCursorSettingsControls()
        refreshAutoClickerSettingsControls()
        refreshCursorMovementButtons()
        return container
    }

    private func configureTabView() {
        tabView.tabViewType = .topTabsBezelBorder
        tabView.addTabViewItem(tabItem(.shortcuts, view: makeShortcutsSection()))
        tabView.addTabViewItem(tabItem(.scrolling, view: makeScrollSettingsSection()))
        tabView.addTabViewItem(tabItem(.cursorControl, view: makeCursorSettingsSection()))
        tabView.addTabViewItem(tabItem(.halo, view: makeHaloSettingsSection()))
        tabView.addTabViewItem(tabItem(.autoClicker, view: makeAutoClickerSettingsSection()))
        tabView.selectTabViewItem(at: 0)
    }

    private func tabItem(_ section: SettingsSection, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: section.rawValue)
        item.label = section.title
        item.view = paddedTabContent(view)
        return item
    }

    private func paddedTabContent(_ content: NSView) -> NSView {
        let flippedContent = FlippedView()
        flippedContent.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        flippedContent.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: flippedContent.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: flippedContent.trailingAnchor),
            content.topAnchor.constraint(equalTo: flippedContent.topAnchor),
            content.bottomAnchor.constraint(equalTo: flippedContent.bottomAnchor)
        ])

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = flippedContent
        
        // Disable horizontal scrolling
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none

        let container = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            flippedContent.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        return container
    }

    func setCursorModeActive(_ active: Bool) {
        entryModeButton?.state = active ? .on : .off
        entryModeButton?.title = active ? "Entry is on — Exit mode" : "Entry is off — Enter mode"
        entryStatusLabel?.stringValue = active ? "Keyboard mouse controls are active." : "Normal typing. Mouse shortcuts are inactive."
        entryStatusLabel?.textColor = active ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func toggleEntryMode(_ sender: NSButton) {
        setCursorModeActive(onToggleCursorMode())
    }

    private func makeEntrySection() -> NSView {
        let title = NSTextField(labelWithString: "Entry")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let status = NSTextField(labelWithString: "Normal typing. Mouse shortcuts are inactive.")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        entryStatusLabel = status
        let labels = NSStackView(views: [title, status])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5

        let toggle = NSButton(title: "Entry is off — Enter mode", target: self, action: #selector(toggleEntryMode(_:)))
        toggle.setButtonType(.pushOnPushOff)
        toggle.bezelStyle = .rounded
        toggle.controlSize = .large
        toggle.font = .systemFont(ofSize: 17, weight: .semibold)
        toggle.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        toggle.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        entryModeButton = toggle
        let header = NSStackView(views: [labels, NSView(), toggle])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        let shortcut = makeShortcutRow(for: .activateCursorMode)
        shortcutButtons[.activateCursorMode]?.font = .systemFont(ofSize: 18, weight: .medium)
        shortcutButtons[.activateCursorMode]?.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        let separateExit = NSButton(checkboxWithTitle: "Use a different key to exit", target: self, action: #selector(modeOptionsChanged(_:)))
        separateExitCheckbox = separateExit
        let exitRow = makeShortcutRow(for: .exitCursorMode)
        exitShortcutRow = exitRow
        let scope = NSTextField(wrappingLabelWithString: "All movement, scrolling, and action shortcuts below require Entry to be on. Settings always stay editable.")
        scope.font = .systemFont(ofSize: 12)
        scope.textColor = .secondaryLabelColor
        let content = NSStackView(views: [header, shortcut, separateExit, exitRow, scope])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        for row in [header, shortcut, exitRow] {
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        content.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        content.layer?.borderColor = NSColor.separatorColor.cgColor
        content.layer?.borderWidth = 1
        content.layer?.cornerRadius = 12
        refreshModeOptions()
        return content
    }

    private func refreshModeOptions() {
        let options = modeOptionsProvider()
        separateExitCheckbox?.state = options.separateExitEnabled ? .on : .off
        exitShortcutRow?.isHidden = !options.separateExitEnabled
        shortcutButtons[.exitCursorMode]?.isEnabled = options.separateExitEnabled
    }

    @objc private func modeOptionsChanged(_ sender: NSButton) {
        let options = CursorModeOptions(
            separateExitEnabled: separateExitCheckbox?.state == .on
        )
        onModeOptionsChange(options)
        refreshModeOptions()
    }

    private func makeShortcutsSection() -> NSView {
        let sectionLabel = sectionDescription(
            title: "Shortcuts",
            body: "These shortcuts work only while Entry is on. Plain keys are supported. You can edit settings at any time."
        )

        let shortcutStack = NSStackView()
        shortcutStack.orientation = .vertical
        shortcutStack.alignment = .leading
        shortcutStack.spacing = 16

        for identifier in ShortcutIdentifier.allCases where identifier != .activateCursorMode && identifier != .exitCursorMode {
            shortcutStack.addArrangedSubview(makeShortcutRow(for: identifier))
        }

        let clickDescription = sectionDescription(
            title: "Mouse Controls",
            body: "Fixed mouse-button controls available while cursor control mode is active."
        )

        let clickStack = NSStackView()
        clickStack.orientation = .vertical
        clickStack.alignment = .leading
        clickStack.spacing = 16
        clickStack.addArrangedSubview(
            fixedShortcutRow(
                title: "Left click",
                description: "Clicks once at the current cursor location.",
                shortcut: "Return"
            )
        )
        clickStack.addArrangedSubview(
            fixedShortcutRow(
                title: "Right click",
                description: "Opens context menus and secondary-click actions.",
                shortcut: "Shift-Return or Control-Return"
            )
        )
        clickStack.addArrangedSubview(
            fixedShortcutRow(
                title: "Drag or draw",
                description: "Holds the left mouse button until Shift is released.",
                shortcut: "Hold Shift"
            )
        )

        let stack = NSStackView(views: [sectionLabel, shortcutStack, makeSeparator(), clickDescription, clickStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 32
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)
        return stack
    }

    private func makeScrollSettingsSection() -> NSView {
        let sectionLabel = sectionDescription(
            title: "Scrolling",
            body: "Fine-tune universal scrolling. Use exact numeric values for tiny one-pixel nudges or larger fast-scroll movement."
        )

        let rows: [(ScrollSettingKey, String, String, Double, Double, Bool, String)] = [
            (
                .pixelDelta,
                "Base distance",
                "Pixels sent by one scroll event before multipliers and acceleration.",
                Double(ScrollSettings.minimumPixelDelta),
                Double(ScrollSettings.maximumPixelDelta),
                true,
                "px"
            ),
            (
                .eventsPerShortcut,
                "Events per repeat",
                "How many scroll events Cursor Control sends for each shortcut press or repeat.",
                Double(ScrollSettings.minimumEventsPerShortcut),
                Double(ScrollSettings.maximumEventsPerShortcut),
                true,
                "events"
            ),
            (
                .accelerationPerRepeat,
                "Hold acceleration",
                "Extra multiplier added for every held-key repeat. Use 0 for perfectly linear scrolling.",
                ScrollSettings.minimumAccelerationPerRepeat,
                ScrollSettings.maximumAccelerationPerRepeat,
                false,
                "x/repeat"
            ),
            (
                .maximumAccelerationMultiplier,
                "Acceleration cap",
                "Maximum multiplier allowed while holding a scroll shortcut.",
                ScrollSettings.minimumMaximumMultiplier,
                ScrollSettings.maximumMaximumMultiplier,
                false,
                "x"
            )
        ]

        let stack = NSStackView(views: [sectionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 32
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)

        for row in rows {
            let control = NumericSettingControl(
                minimum: row.3,
                maximum: row.4,
                isInteger: row.5,
                suffix: row.6,
                target: self,
                action: #selector(scrollSettingChanged(_:))
            )
            scrollControls[row.0] = control
            stack.addArrangedSubview(control.row(title: row.1, description: row.2))
        }

        return stack
    }

    private func makeCursorSettingsSection() -> NSView {
        let sectionLabel = sectionDescription(
            title: "Cursor Control",
            body: "Tune Vim cursor movement for both pixel-level control and fast corner-to-corner travel."
        )

        let rows: [(CursorSettingKey, String, String, Double, Double, Bool, String)] = [
            (
                .initialSpeed,
                "Initial speed",
                "Pixels moved by the first movement frame. Lower values make single taps more precise.",
                CursorSettings.minimumInitialSpeed,
                CursorSettings.maximumInitialSpeed,
                false,
                "px/frame"
            ),
            (
                .maximumSpeed,
                "Maximum speed",
                "Top cursor speed while holding a movement key.",
                CursorSettings.minimumMaximumSpeed,
                CursorSettings.maximumMaximumSpeed,
                false,
                "px/frame"
            ),
            (
                .accelerationPerFrame,
                "Acceleration",
                "How quickly held cursor movement ramps from initial speed to maximum speed.",
                CursorSettings.minimumAccelerationPerFrame,
                CursorSettings.maximumAccelerationPerFrame,
                false,
                "px/frame²"
            )
        ]

        let stack = NSStackView(views: [sectionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)

        for row in rows {
            let control = NumericSettingControl(
                minimum: row.3,
                maximum: row.4,
                isInteger: row.5,
                suffix: row.6,
                target: self,
                action: #selector(cursorSettingChanged(_:))
            )
            cursorControls[row.0] = control
            stack.addArrangedSubview(control.row(title: row.1, description: row.2))
        }


        stack.addArrangedSubview(makeSeparator())
        
        let bindingDescription = sectionDescription(
            title: "Movement Keys",
            body: "Choose the keys Cursor Control captures while cursor control mode is active. Hold Shift to drag or draw while moving."
        )
        stack.addArrangedSubview(bindingDescription)

        let bindingStack = NSStackView()
        bindingStack.orientation = .vertical
        bindingStack.alignment = .leading
        bindingStack.spacing = 7

        for direction in CursorMovementDirection.allCases {
            bindingStack.addArrangedSubview(makeCursorMovementRow(for: direction))
        }
        stack.addArrangedSubview(bindingStack)

        return stack
    }


    private func makeAutoClickerSettingsSection() -> NSView {
        let sectionLabel = sectionDescription(
            title: "Auto Clicker",
            body: "Configure the global auto-clicker shortcut and click rate."
        )

        let stack = NSStackView(views: [sectionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 32
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)

        stack.addArrangedSubview(makeShortcutRow(for: .autoClicker))

        let control = NumericSettingControl(
            minimum: AutoClickerSettings.minimumClicksPerSecond,
            maximum: AutoClickerSettings.maximumClicksPerSecond,
            isInteger: true,
            suffix: "clicks/sec",
            target: self,
            action: #selector(autoClickerSettingChanged(_:))
        )
        autoClickerControls[.clicksPerSecond] = control
        stack.addArrangedSubview(control.row(title: "Click Rate", description: "How many clicks to simulate per second."))

        return stack
    }

    private func makeHaloSettingsSection() -> NSView {
        let sectionLabel = sectionDescription(
            title: "Halo Settings",
            body: "Customize the appearance of the cursor mode indicator."
        )

        let rows: [(CursorSettingKey, String, String, Double, Double, Bool, String)] = [
            (
                .haloSize,
                "Halo Size",
                "Size of the solid center blob.",
                CursorSettings.minimumHaloSize,
                CursorSettings.maximumHaloSize,
                false,
                "px"
            ),
            (
                .haloOpacity,
                "Halo Opacity",
                "Transparency of the halo trail (0.1 to 1.0).",
                CursorSettings.minimumHaloOpacity,
                CursorSettings.maximumHaloOpacity,
                false,
                "alpha"
            )
        ]

        let stack = NSStackView(views: [sectionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)

        for row in rows {
            let control = NumericSettingControl(
                minimum: row.3,
                maximum: row.4,
                isInteger: row.5,
                suffix: row.6,
                target: self,
                action: #selector(cursorSettingChanged(_:))
            )
            cursorControls[row.0] = control
            stack.addArrangedSubview(control.row(title: row.1, description: row.2))
        }

        let haloColorLabel = NSTextField(labelWithString: "Indicator color")
        haloColorLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        
        let haloColorDescription = NSTextField(wrappingLabelWithString: "Color of the cursor mode indicator trail and dot.")
        haloColorDescription.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        haloColorDescription.textColor = .secondaryLabelColor
        haloColorDescription.maximumNumberOfLines = 2
        
        let haloColorLabelStack = NSStackView(views: [haloColorLabel, haloColorDescription])
        haloColorLabelStack.orientation = .vertical
        haloColorLabelStack.alignment = .leading
        haloColorLabelStack.spacing = 2
        haloColorLabelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

        let colorButtonsStack = NSStackView()
        colorButtonsStack.orientation = .horizontal
        colorButtonsStack.spacing = 8
        colorButtonsStack.alignment = .centerY

        for color in HaloColor.allCases {
            let button = ColorButton(haloColor: color, target: self, action: #selector(haloColorButtonTapped(_:)))
            colorButtonsStack.addArrangedSubview(button)
            haloColorButtons[color] = button
        }
        
        let haloColorRow = NSStackView(views: [haloColorLabelStack, colorButtonsStack])
        haloColorRow.orientation = .horizontal
        haloColorRow.alignment = .centerY
        haloColorRow.spacing = 16
        haloColorRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        
        stack.addArrangedSubview(haloColorRow)

        return stack
    }

    private func sectionDescription(title: String, body: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.maximumNumberOfLines = 0

        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func makeShortcutRow(for identifier: ShortcutIdentifier) -> NSView {
        let titleLabel = NSTextField(labelWithString: identifier == .activateCursorMode ? "Entry shortcut" : identifier.title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let descriptionLabel = NSTextField(wrappingLabelWithString: identifier == .activateCursorMode ? "Record a key combination or tap Left or Right Option." : identifier.settingsDescription)
        descriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        let labelStack = NSStackView(views: [titleLabel, descriptionLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3

        let button = ShortcutRecorderButton(shortcutIdentifier: identifier)
        button.target = self
        button.action = #selector(beginShortcutRecording(_:))
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        button.onCapturedShortcut = { [weak self, weak button] shortcut in
            guard let self, let button else { return }
            self.finishShortcutRecording(button, shortcut: shortcut)
        }
        button.onCancelledRecording = { [weak self] in
            self?.cancelShortcutRecording()
        }
        shortcutButtons[identifier] = button

        let row = NSStackView(views: [labelStack, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return row
    }

    private func fixedShortcutRow(title: String, description: String, shortcut: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        let labelStack = NSStackView(views: [titleLabel, descriptionLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        let shortcutButton = NSButton(title: shortcut, target: nil, action: nil)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.isEnabled = false
        shortcutButton.toolTip = "Fixed shortcut"
        shortcutButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        shortcutButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let row = NSStackView(views: [labelStack, shortcutButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeCursorMovementRow(for direction: CursorMovementDirection) -> NSView {
        let titleLabel = NSTextField(labelWithString: direction.settingsTitle)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let descriptionLabel = NSTextField(wrappingLabelWithString: direction.settingsDescription)
        descriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        let labelStack = NSStackView(views: [titleLabel, descriptionLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3

        let button = ShortcutRecorderButton(cursorMovementDirection: direction)
        button.target = self
        button.action = #selector(beginShortcutRecording(_:))
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        button.onCapturedShortcut = { [weak self, weak button] shortcut in
            guard let self, let button else { return }
            self.finishShortcutRecording(button, shortcut: shortcut)
        }
        button.onCancelledRecording = { [weak self] in
            self?.cancelShortcutRecording()
        }
        cursorMovementButtons[direction] = button

        let row = NSStackView(views: [labelStack, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return row
    }

    @objc private func beginShortcutRecording(_ sender: ShortcutRecorderButton) {
        for button in shortcutButtons.values where button !== sender && button.isRecordingShortcut {
            button.cancelRecording()
        }
        for button in cursorMovementButtons.values where button !== sender && button.isRecordingShortcut {
            button.cancelRecording()
        }

        showMessage("Press the new key for \(sender.recorderTarget.title), or Esc to cancel.", isError: false)
        onRecordingStateChanged(true)
        sender.beginRecording()
        startRecordingEventMonitor(for: sender)
    }

    private func finishShortcutRecording(
        _ button: ShortcutRecorderButton,
        shortcut: KeyboardShortcut
    ) {
        stopRecordingEventMonitor()

        switch button.recorderTarget {
        case .globalShortcut(let identifier):
            finishGlobalShortcutRecording(button, identifier: identifier, shortcut: shortcut)
        case .cursorMovement(let direction):
            finishCursorMovementRecording(button, direction: direction, shortcut: shortcut)
        }
    }

    private func finishGlobalShortcutRecording(
        _ button: ShortcutRecorderButton,
        identifier: ShortcutIdentifier,
        shortcut: KeyboardShortcut
    ) {
        let result = onShortcutChange(identifier, shortcut)
        refreshModeOptions()
        refreshShortcutButtons()
        button.finishRecording(displayTitle: shortcutProvider(identifier).displayName)
        onRecordingStateChanged(false)

        switch result {
        case .success:
            showMessage("Updated \(identifier.title) to \(shortcut.displayName).", isError: false)
        case .validationFailure(let message):
            showMessage(message, isError: true)
        case .registrationFailure(let message):
            showMessage(message, isError: true)
        }
    }

    private func finishCursorMovementRecording(
        _ button: ShortcutRecorderButton,
        direction: CursorMovementDirection,
        shortcut: KeyboardShortcut
    ) {
        let result = onCursorMovementBindingChange(direction, shortcut)
        refreshCursorMovementButtons()
        button.finishRecording(displayTitle: cursorMovementBindingProvider(direction).displayName)
        onRecordingStateChanged(false)

        switch result {
        case .success:
            showMessage("Updated \(direction.settingsTitle.lowercased()) to \(shortcut.displayName).", isError: false)
        case .failure(let error):
            showMessage(error.localizedDescription, isError: true)
        }
    }

    @objc private func restoreDefaults() {
        onModeOptionsChange(CursorModeOptions())
        let result = onRestoreDefaults()
        let scrollSettings = onRestoreScrollSettingsDefaults()
        let cursorSettings = onRestoreCursorSettingsDefaults()
        let autoClickerSettings = onRestoreAutoClickerSettingsDefaults()
        _ = onRestoreCursorMovementBindingsDefaults()
        refreshModeOptions()
        refreshShortcutButtons()
        refreshScrollSettingsControls(with: scrollSettings)
        refreshCursorSettingsControls(with: cursorSettings)
        refreshAutoClickerSettingsControls(with: autoClickerSettings)
        refreshCursorMovementButtons()

        switch result {
        case .success:
            showMessage("Restored all Cursor Control defaults.", isError: false)
        case .validationFailure(let message), .registrationFailure(let message):
            showMessage(message, isError: true)
        }
    }

    private func refreshShortcutButtons() {
        for (identifier, button) in shortcutButtons {
            guard !button.isRecordingShortcut else { continue }
            button.title = shortcutProvider(identifier).displayName
        }
    }

    private func refreshCursorMovementButtons() {
        for (direction, button) in cursorMovementButtons {
            guard !button.isRecordingShortcut else { continue }
            button.title = cursorMovementBindingProvider(direction).displayName
        }
    }

    @objc private func scrollSettingChanged(_ sender: Any) {
        let currentSettings = scrollSettingsProvider()
        let settings = ScrollSettings(
            pixelDelta: Int32(readScroll(.pixelDelta, sender: sender)),
            eventsPerShortcut: Int(readScroll(.eventsPerShortcut, sender: sender)),
            accelerationPerRepeat: readScroll(.accelerationPerRepeat, sender: sender),
            maximumAccelerationMultiplier: readScroll(.maximumAccelerationMultiplier, sender: sender),
            verticalMultiplier: currentSettings.verticalMultiplier,
            horizontalMultiplier: currentSettings.horizontalMultiplier
        )
        onScrollSettingsChange(settings)
        refreshScrollSettingsControls(with: settings)
        showMessage("Updated scroll tuning.", isError: false)
    }


    @objc private func autoClickerSettingChanged(_ sender: Any) {
        var settings = autoClickerSettingsProvider()
        settings.clicksPerSecond = readAutoClicker(.clicksPerSecond, sender: sender)
        onAutoClickerSettingsChange(settings)
        refreshAutoClickerSettingsControls(with: settings)
        showMessage("Updated auto-clicker settings.", isError: false)
    }

    private func readAutoClicker(_ key: AutoClickerSettingKey, sender: Any?) -> Double {
        autoClickerControls[key]?.value(sender: sender) ?? 0
    }

    private func refreshAutoClickerSettingsControls(with settings: AutoClickerSettings? = nil) {
        let settings = settings ?? autoClickerSettingsProvider()
        autoClickerControls[.clicksPerSecond]?.setValue(settings.clicksPerSecond)
    }

    @objc private func cursorSettingChanged(_ sender: Any) {
        var settings = cursorSettingsProvider()
        settings.initialSpeed = readCursor(.initialSpeed, sender: sender)
        settings.maximumSpeed = readCursor(.maximumSpeed, sender: sender)
        settings.accelerationPerFrame = readCursor(.accelerationPerFrame, sender: sender)
        settings.haloSize = readCursor(.haloSize, sender: sender)
        settings.haloOpacity = readCursor(.haloOpacity, sender: sender)
        onCursorSettingsChange(settings)
        refreshCursorSettingsControls(with: settings)
        showMessage("Updated cursor-control tuning.", isError: false)
    }

    @objc private func haloColorButtonTapped(_ sender: ColorButton) {
        var settings = cursorSettingsProvider()
        settings.haloColor = sender.haloColor
        onCursorSettingsChange(settings)
        refreshCursorSettingsControls(with: settings)
        showMessage("Updated indicator color.", isError: false)
    }

    private func readScroll(_ key: ScrollSettingKey, sender: Any?) -> Double {
        scrollControls[key]?.value(sender: sender) ?? 0
    }

    private func readCursor(_ key: CursorSettingKey, sender: Any?) -> Double {
        cursorControls[key]?.value(sender: sender) ?? 0
    }

    private func refreshScrollSettingsControls(with settings: ScrollSettings? = nil) {
        let settings = settings ?? scrollSettingsProvider()
        scrollControls[.pixelDelta]?.setValue(Double(settings.pixelDelta))
        scrollControls[.eventsPerShortcut]?.setValue(Double(settings.eventsPerShortcut))
        scrollControls[.accelerationPerRepeat]?.setValue(settings.accelerationPerRepeat)
        scrollControls[.maximumAccelerationMultiplier]?.setValue(settings.maximumAccelerationMultiplier)
        scrollControls[.verticalMultiplier]?.setValue(settings.verticalMultiplier)
        scrollControls[.horizontalMultiplier]?.setValue(settings.horizontalMultiplier)
    }

    private func refreshCursorSettingsControls(with settings: CursorSettings? = nil) {
        let settings = settings ?? cursorSettingsProvider()
        cursorControls[.initialSpeed]?.setValue(settings.initialSpeed)
        cursorControls[.maximumSpeed]?.setValue(settings.maximumSpeed)
        cursorControls[.accelerationPerFrame]?.setValue(settings.accelerationPerFrame)
        cursorControls[.frameRate]?.setValue(settings.frameRate)
        cursorControls[.haloSize]?.setValue(settings.haloSize)
        cursorControls[.haloOpacity]?.setValue(settings.haloOpacity)
        for (color, button) in haloColorButtons {
            button.isSelectedColor = (color == settings.haloColor)
        }
    }

    private func showMessage(_ message: String, isError: Bool) {
        messageLabel.stringValue = message
        messageLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func startRecordingEventMonitor(for button: ShortcutRecorderButton) {
        stopRecordingEventMonitor()
        recordingEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel
        ]) {
            [weak button] event in
            guard let button, button.isRecordingShortcut else {
                return event
            }

            button.capture(event)
            switch event.type {
            case .keyDown, .keyUp, .flagsChanged:
                return nil
            default:
                return event
            }
        }
    }

    private func stopRecordingEventMonitor() {
        if let recordingEventMonitor {
            NSEvent.removeMonitor(recordingEventMonitor)
            self.recordingEventMonitor = nil
        }
    }

    private func cancelShortcutRecording() {
        stopRecordingEventMonitor()
        onRecordingStateChanged(false)
        showMessage("Recording cancelled.", isError: false)
    }
}

private class ColorButton: NSButton {
    let haloColor: HaloColor
    var isSelectedColor: Bool = false {
        didSet { needsDisplay = true }
    }
    
    init(haloColor: HaloColor, target: AnyObject?, action: Selector?) {
        self.haloColor = haloColor
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.setButtonType(.momentaryPushIn)
        self.toolTip = haloColor.displayName
        
        self.widthAnchor.constraint(equalToConstant: 24).isActive = true
        self.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let size = min(bounds.width, bounds.height)
        let rect = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
        haloColor.nsColor.setFill()
        path.fill()
        
        if isSelectedColor {
            let strokePath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor.controlAccentColor.setStroke()
            strokePath.lineWidth = 2.0
            strokePath.stroke()
        } else {
            let strokePath = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            strokePath.lineWidth = 1.0
            strokePath.stroke()
        }
    }
}
