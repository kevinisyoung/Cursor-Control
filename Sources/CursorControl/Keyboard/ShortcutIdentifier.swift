enum ShortcutIdentifier: String, CaseIterable, Codable, Hashable {
    case activateCursorMode
    case scrollLeft
    case scrollDown
    case scrollUp
    case scrollRight
    case autoClicker
    case middleClick
    case mouseJiggler

    static let eventTapHandledCases: [ShortcutIdentifier] = [
        .scrollLeft,
        .scrollDown,
        .scrollUp,
        .scrollRight,
        .autoClicker
    ]

    static let carbonHandledCases: [ShortcutIdentifier] = allCases.filter {
        !eventTapHandledCases.contains($0)
    }

    var supportsPlainKey: Bool {
        switch self {
        case .scrollLeft, .scrollDown, .scrollUp, .scrollRight: return true
        default: return false
        }
    }

    func requiresCursorMode(for shortcut: KeyboardShortcut) -> Bool {
        supportsPlainKey && shortcut.modifiers.intersection([.command, .control, .option]).isEmpty
    }

    var hotKeyID: UInt32 {
        switch self {
        case .activateCursorMode:
            return 1
        case .scrollLeft:
            return 2
        case .scrollDown:
            return 3
        case .scrollUp:
            return 4
        case .scrollRight:
            return 5
        case .autoClicker:
            return 6
        case .middleClick:
            return 7
        case .mouseJiggler:
            return 8
        }
    }

    var title: String {
        switch self {
        case .activateCursorMode:
            return "Cursor control mode"
        case .scrollLeft:
            return "Scroll left"
        case .scrollDown:
            return "Scroll down"
        case .scrollUp:
            return "Scroll up"
        case .scrollRight:
            return "Scroll right"
        case .autoClicker:
            return "Auto clicker"
        case .middleClick: return "Middle-Click"
        case .mouseJiggler: return "Keep Awake (Mouse Jiggler)"
        }
    }

    var settingsDescription: String {
        switch self {
        case .activateCursorMode:
            return "Enter or exit keyboard cursor-control mode."
        case .scrollLeft:
            return "Scroll the frontmost app left."
        case .scrollDown:
            return "Scroll the frontmost app down."
        case .scrollUp:
            return "Scroll the frontmost app up."
        case .scrollRight:
            return "Scroll the frontmost app right."
        case .autoClicker:
            return "Toggle the auto-clicker on or off."
        case .middleClick:
            return "Simulates a middle-click at the current cursor position."
        case .mouseJiggler:
            return "Keeps your Mac awake by slightly nudging the cursor when you're inactive."
        }
    }
}
