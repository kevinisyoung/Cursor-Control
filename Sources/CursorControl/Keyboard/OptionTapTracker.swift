import CoreGraphics

/// Recognizes a quick, unchorded tap without consuming the modifier's events.
/// Shared by the shortcut recorder and the global input event tap.
struct OptionTapTracker {
    static let maximumDuration = 0.25
    private var heldKeys: Set<UInt32> = []
    private var heldMouseButtons: Set<CGEventType> = []
    private var pending: (keyCode: UInt32, startedAt: Double)?

    mutating func reset() {
        pending = nil
        heldKeys.removeAll()
        heldMouseButtons.removeAll()
    }

    mutating func handle(
        type: CGEventType,
        keyCode: UInt32,
        flags: CGEventFlags,
        timestamp: Double
    ) -> KeyboardShortcut? {
        switch type {
        case .keyDown: heldKeys.insert(keyCode)
        case .keyUp: heldKeys.remove(keyCode)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: heldMouseButtons.insert(type)
        case .leftMouseUp: heldMouseButtons.remove(.leftMouseDown)
        case .rightMouseUp: heldMouseButtons.remove(.rightMouseDown)
        case .otherMouseUp: heldMouseButtons.remove(.otherMouseDown)
        default: break
        }
        guard type == .flagsChanged else {
            pending = nil
            return nil
        }
        guard let shortcut = KeyboardShortcut.optionTap(keyCode: keyCode) else {
            pending = nil
            return nil
        }

        // NX_DEVICELALTKEYMASK and NX_DEVICERALTKEYMASK distinguish physical sides,
        // including when both Option keys are held (the aggregate flag cannot).
        let sideMask: UInt64 = keyCode == 58 ? 0x20 : 0x40
        let otherSideMask: UInt64 = keyCode == 58 ? 0x40 : 0x20
        let isDown = flags.rawValue & sideMask != 0
        let modifiers = ShortcutModifiers(cgEventFlags: flags)
        if isDown {
            if pending == nil, heldKeys.isEmpty, heldMouseButtons.isEmpty, modifiers == [.option],
               flags.rawValue & otherSideMask == 0,
               !flags.contains(.maskSecondaryFn) {
                pending = (keyCode, timestamp)
            } else {
                pending = nil
            }
            return nil
        }

        let candidate = pending
        pending = nil
        guard let candidate, candidate.keyCode == keyCode,
              modifiers.isEmpty, !flags.contains(.maskSecondaryFn),
              timestamp >= candidate.startedAt,
              timestamp - candidate.startedAt <= Self.maximumDuration else {
            return nil
        }
        return shortcut
    }
}
