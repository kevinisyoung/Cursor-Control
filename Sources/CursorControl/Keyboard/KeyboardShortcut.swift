import AppKit

struct KeyboardShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers
    let keyEquivalent: String
    let displayKey: String

    init(
        keyCode: UInt32,
        modifiers: ShortcutModifiers,
        keyEquivalent: String,
        displayKey: String
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyEquivalent = keyEquivalent
        self.displayKey = displayKey
    }

    init?(event: NSEvent, requiresPrimaryModifier: Bool = true) {
        let modifiers = ShortcutModifiers(eventModifiers: event.modifierFlags)
        if requiresPrimaryModifier,
           modifiers.intersection([.command, .control, .option]).isEmpty {
            return nil
        }

        let keyEquivalent = KeyboardShortcut.keyEquivalent(from: event)
        guard !keyEquivalent.isEmpty else {
            return nil
        }

        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyEquivalent: keyEquivalent,
            displayKey: KeyboardShortcut.displayKey(
                keyCode: event.keyCode,
                keyEquivalent: keyEquivalent
            )
        )
    }

    static func optionTap(keyCode: UInt32) -> KeyboardShortcut? {
        guard keyCode == 58 || keyCode == 61 else { return nil }
        return KeyboardShortcut(
            keyCode: keyCode,
            modifiers: [],
            keyEquivalent: "",
            displayKey: keyCode == 58 ? "Left Option tap" : "Right Option tap"
        )
    }

    var isOptionTap: Bool {
        Self.optionTap(keyCode: keyCode) != nil && modifiers.isEmpty
    }

    var displayName: String {
        let prefix = modifiers.displayPrefix
        return prefix.isEmpty ? displayKey : "\(prefix)-\(displayKey)"
    }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        modifiers.eventModifierFlags
    }

    private static func keyEquivalent(from event: NSEvent) -> String {
        if event.keyCode == 49 {
            return " "
        }

        if event.keyCode == KeyboardShortcuts.escapeKeyCode {
            return "\u{1b}"
        }

        if KeyboardShortcuts.returnKeyCodes.contains(event.keyCode) {
            return "\r"
        }

        guard let character = event.charactersIgnoringModifiers?.lowercased(),
              character.count == 1 else {
            return ""
        }

        return character
    }

    private static func displayKey(keyCode: UInt16, keyEquivalent: String) -> String {
        switch keyCode {
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        case 49:
            return "Space"
        case KeyboardShortcuts.escapeKeyCode:
            return "Escape"
        case let key where KeyboardShortcuts.returnKeyCodes.contains(key):
            return "Return"
        default:
            return keyEquivalent.uppercased()
        }
    }
}
