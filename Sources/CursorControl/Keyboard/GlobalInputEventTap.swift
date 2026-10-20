@preconcurrency import CoreGraphics
import OSLog

private func globalInputEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let context else {
        return Unmanaged.passUnretained(event)
    }

    let eventTap = Unmanaged<GlobalInputEventTap>
        .fromOpaque(context)
        .takeUnretainedValue()
    return MainActor.assumeIsolated {
        return eventTap.handle(type: type, event: event)
    }
}

private struct CursorInputHandling {
    let input: CursorControlInput?
}

@MainActor
final class GlobalInputEventTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcuts: [ShortcutIdentifier: KeyboardShortcut] = [:]
    private var cursorMovementBindings = CursorMovementBindings()
    private var onShortcut: (@MainActor (ShortcutIdentifier, CGEventType, Int) -> Void)?
    private var onCursorInput: ((CursorControlInput) -> Void)?
    private var onTapDisabled: (() -> Void)?
    private var isCursorModeActive = false
    private var isDragModifierDown = false
    private var cursorCaptureMode: CursorControlCaptureMode = .movement
    private var repeatingShortcutIdentifier: ShortcutIdentifier?
    private var shortcutRepeatCount = 0
    private var optionTapTracker = OptionTapTracker()
    private let logger = Logger(
        subsystem: AppConstants.bundleIdentifier,
        category: "GlobalInputEventTap"
    )

    @discardableResult
    func start(
        shortcuts: [ShortcutIdentifier: KeyboardShortcut],
        cursorMovementBindings: CursorMovementBindings,
        onShortcut: @escaping @MainActor (ShortcutIdentifier, CGEventType, Int) -> Void,
        onCursorInput: @escaping (CursorControlInput) -> Void,
        onTapDisabled: @escaping () -> Void
    ) -> Bool {
        stop()
        self.shortcuts = shortcuts
        self.cursorMovementBindings = cursorMovementBindings
        self.onShortcut = onShortcut
        self.onCursorInput = onCursorInput
        self.onTapDisabled = onTapDisabled

        let eventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: globalInputEventTapCallback,
            userInfo: context
        ) else {
            logger.error("Could not create global input event tap")
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
            logger.error("Could not create global input event tap run loop source")
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.notice("Started global input event tap")
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        shortcuts.removeAll()
        onShortcut = nil
        onCursorInput = nil
        onTapDisabled = nil
        isCursorModeActive = false
        isDragModifierDown = false
        cursorCaptureMode = .movement
        repeatingShortcutIdentifier = nil
        shortcutRepeatCount = 0
        optionTapTracker.reset()
    }

    func setCursorModeActive(
        _ isActive: Bool,
        captureMode: CursorControlCaptureMode = .movement
    ) {
        isCursorModeActive = isActive
        if !isActive {
            isDragModifierDown = false
        }
        cursorCaptureMode = captureMode
    }

    func setCursorCaptureMode(_ captureMode: CursorControlCaptureMode) {
        cursorCaptureMode = captureMode
    }

    func setCursorMovementBindings(_ bindings: CursorMovementBindings) {
        cursorMovementBindings = bindings
    }

    fileprivate func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            optionTapTracker.reset()
            onTapDisabled?()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = ShortcutModifiers(cgEventFlags: event.flags)

        if let tap = optionTapTracker.handle(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            timestamp: Double(event.timestamp) / 1_000_000_000
        ), shortcuts[.activateCursorMode] == tap {
            onShortcut?(.activateCursorMode, .keyDown, 0)
        }

        // 1. Check if the currently held shortcut is released
        if let activeId = repeatingShortcutIdentifier, let activeShortcut = shortcuts[activeId] {
            var released = false
            if type == .keyUp && keyCode == activeShortcut.keyCode {
                released = true
            } else if type == .flagsChanged && !modifiers.isSuperset(of: activeShortcut.modifiers) {
                released = true
            }

            if released {
                repeatingShortcutIdentifier = nil
                shortcutRepeatCount = 0
                onShortcut?(activeId, .keyUp, 0)
                
                // Consume the keyUp event if it was for the main key
                if type == .keyUp && keyCode == activeShortcut.keyCode {
                    return nil
                }
            }
        }

        // 2. flagsChanged handling
        if type == .flagsChanged {
            return handleFlagsChanged(event)
        }

        // 3. keyDown / keyUp handling for everything else
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        if let cursorInput = cursorInput(
            keyCode: keyCode,
            modifiers: modifiers,
            isKeyDown: type == .keyDown
        ) {
            if let input = cursorInput.input {
                onCursorInput?(input)
            }
            return nil
        }

        guard let identifier = Self.shortcutIdentifier(
            for: keyCode,
            modifiers: modifiers,
            shortcuts: shortcuts
        ) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            // Already handled in the released block, but catch-all here
            if repeatingShortcutIdentifier == identifier {
                repeatingShortcutIdentifier = nil
                shortcutRepeatCount = 0
                onShortcut?(identifier, type, 0)
            }
            return nil
        }

        if repeatingShortcutIdentifier == identifier {
            shortcutRepeatCount += 1
        } else {
            repeatingShortcutIdentifier = identifier
            shortcutRepeatCount = 0
        }
        onShortcut?(identifier, type, shortcutRepeatCount)

        return nil
    }

    private func cursorInput(
        keyCode: UInt32,
        modifiers: ShortcutModifiers,
        isKeyDown: Bool
    ) -> CursorInputHandling? {
        guard isCursorModeActive else { return nil }

        if keyCode == UInt32(KeyboardShortcuts.escapeKeyCode) {
            return nil
        }

        if KeyboardShortcuts.returnKeyCodes.contains(UInt16(keyCode)) {
            let isSupportedClickShortcut = modifiers.isEmpty
                || modifiers == [.shift]
                || modifiers == [.control]
            guard isSupportedClickShortcut else {
                return nil
            }

            return CursorInputHandling(
                input: CursorControlInput(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    isKeyDown: isKeyDown,
                    captureMode: cursorCaptureMode,
                    movementBindings: cursorMovementBindings
                )
            )
        }

        guard let input = CursorControlInput(
            keyCode: keyCode,
            modifiers: modifiers,
            isKeyDown: isKeyDown,
            captureMode: cursorCaptureMode,
            movementBindings: cursorMovementBindings
        ) else {
            return nil
        }

        return CursorInputHandling(input: input)
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isCursorModeActive else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = ShortcutModifiers(cgEventFlags: event.flags)
        let isPressed = modifiers.contains(AppConstants.cursorDragModifier)
        guard isPressed != isDragModifierDown else {
            return Unmanaged.passUnretained(event)
        }

        isDragModifierDown = isPressed
        onCursorInput?(.dragHoldChanged(isPressed))
        return nil
    }

    static func shortcutIdentifier(
        for keyCode: UInt32,
        modifiers: ShortcutModifiers,
        shortcuts: [ShortcutIdentifier: KeyboardShortcut]
    ) -> ShortcutIdentifier? {
        for identifier in ShortcutIdentifier.eventTapHandledCases {
            guard let shortcut = shortcuts[identifier],
                  shortcut.keyCode == keyCode,
                  shortcut.modifiers == modifiers else {
                continue
            }

            return identifier
        }

        return nil
    }
}
