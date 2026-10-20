import AppKit

enum KeyboardShortcuts {
    static let escapeKeyCode: UInt16 = 53
    static let returnKeyCodes: Set<UInt16> = [36, 76]
    static let moveLeftKeyCode: UInt32 = 4
    static let moveDownKeyCode: UInt32 = 38
    static let moveUpKeyCode: UInt32 = 40
    static let moveRightKeyCode: UInt32 = 37

    static let defaultGlobalShortcuts: [ShortcutIdentifier: KeyboardShortcut] = [
        .exitCursorMode: KeyboardShortcut(keyCode: 53, modifiers: [], keyEquivalent: "\u{1b}", displayKey: "Escape"),
        .activateCursorMode: KeyboardShortcut(
            keyCode: 13,
            modifiers: [.option],
            keyEquivalent: "w",
            displayKey: "W"
        ),
        .scrollLeft: KeyboardShortcut(
            keyCode: moveLeftKeyCode,
            modifiers: [.control],
            keyEquivalent: "h",
            displayKey: "H"
        ),
        .scrollDown: KeyboardShortcut(
            keyCode: moveDownKeyCode,
            modifiers: [.control],
            keyEquivalent: "j",
            displayKey: "J"
        ),
        .scrollUp: KeyboardShortcut(
            keyCode: moveUpKeyCode,
            modifiers: [.control],
            keyEquivalent: "k",
            displayKey: "K"
        ),
        .scrollRight: KeyboardShortcut(
            keyCode: moveRightKeyCode,
            modifiers: [.control],
            keyEquivalent: "l",
            displayKey: "L"
        ),
        .autoClicker: KeyboardShortcut(
            keyCode: 7,
            modifiers: [.option, .shift],
            keyEquivalent: "x",
            displayKey: "X"
        ),
        .middleClick: KeyboardShortcut(
            keyCode: 46,
            modifiers: [.option],
            keyEquivalent: "m",
            displayKey: "M"
        ),
        .mouseJiggler: KeyboardShortcut(
            keyCode: 38,
            modifiers: [.option],
            keyEquivalent: "j",
            displayKey: "J"
        )
    ]

    static let defaultCursorMovementBindings = CursorMovementBindings(
        left: KeyboardShortcut(
            keyCode: moveLeftKeyCode,
            modifiers: [],
            keyEquivalent: "h",
            displayKey: "H"
        ),
        down: KeyboardShortcut(
            keyCode: moveDownKeyCode,
            modifiers: [],
            keyEquivalent: "j",
            displayKey: "J"
        ),
        up: KeyboardShortcut(
            keyCode: moveUpKeyCode,
            modifiers: [],
            keyEquivalent: "k",
            displayKey: "K"
        ),
        right: KeyboardShortcut(
            keyCode: moveRightKeyCode,
            modifiers: [],
            keyEquivalent: "l",
            displayKey: "L"
        )
    )
}
