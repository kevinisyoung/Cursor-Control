import AppKit

enum ShortcutRecorderTarget: Equatable, Hashable {
    case globalShortcut(ShortcutIdentifier)
    case cursorMovement(CursorMovementDirection)

    var title: String {
        switch self {
        case .globalShortcut(let identifier):
            return identifier.title
        case .cursorMovement(let direction):
            return direction.settingsTitle
        }
    }

    var requiresPrimaryModifier: Bool {
        switch self {
        case .globalShortcut(let identifier):
            return !identifier.supportsPlainKey
        case .cursorMovement:
            return false
        }
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    let recorderTarget: ShortcutRecorderTarget
    var onCapturedShortcut: ((KeyboardShortcut) -> Void)?
    var onCancelledRecording: (() -> Void)?

    private var titleBeforeRecording = ""
    private var optionTapTracker = OptionTapTracker()
    private(set) var isRecordingShortcut = false

    init(shortcutIdentifier: ShortcutIdentifier) {
        self.recorderTarget = .globalShortcut(shortcutIdentifier)
        super.init(frame: .zero)
        configure()
    }

    init(cursorMovementDirection: CursorMovementDirection) {
        self.recorderTarget = .cursorMovement(cursorMovementDirection)
        super.init(frame: .zero)
        configure()
    }

    private func configure() {
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        controlSize = .regular
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func beginRecording() {
        optionTapTracker.reset()
        titleBeforeRecording = title
        isRecordingShortcut = true
        title = "Type shortcut…"
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    func finishRecording(displayTitle: String) {
        optionTapTracker.reset()
        isRecordingShortcut = false
        title = displayTitle
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    func cancelRecording() {
        optionTapTracker.reset()
        isRecordingShortcut = false
        title = titleBeforeRecording
        window?.makeFirstResponder(nil)
        needsDisplay = true
        onCancelledRecording?()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.flagsChanged(with: event)
            return
        }
        capture(event)
    }

    func capture(_ event: NSEvent) {
        guard isRecordingShortcut else { return }
        if recorderTarget == .globalShortcut(.activateCursorMode),
           let cgEvent = event.cgEvent,
           let tap = optionTapTracker.handle(
               type: cgEvent.type,
               keyCode: UInt32(cgEvent.getIntegerValueField(.keyboardEventKeycode)),
               flags: cgEvent.flags,
               timestamp: event.timestamp
           ) {
            onCapturedShortcut?(tap)
            return
        }
        guard event.type == .keyDown else { return }
        if event.keyCode == KeyboardShortcuts.escapeKeyCode,
           recorderTarget != .globalShortcut(.exitCursorMode) {
            cancelRecording()
            return
        }
        guard let shortcut = KeyboardShortcut(
            event: event,
            requiresPrimaryModifier: recorderTarget.requiresPrimaryModifier
        ) else {
            NSSound.beep()
            return
        }
        onCapturedShortcut?(shortcut)
    }
}
