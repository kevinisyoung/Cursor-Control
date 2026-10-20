import AppKit
import Testing
@testable import CursorControl

@MainActor
struct CursorModeOptionsTests {
    @Test func optionsPreserveOldDefaultsAndPersistIndependently() {
        let defaults = UserDefaults(suiteName: "ModeOptionsTests.\(UUID().uuidString)")!
        let store = CursorModeOptionsStore(defaults: defaults)
        #expect(store.load() == CursorModeOptions())
        store.save(CursorModeOptions(separateExitEnabled: true))
        #expect(store.load() == CursorModeOptions(separateExitEnabled: true))
        store.save(CursorModeOptions(separateExitEnabled: false))
        #expect(store.load() == CursorModeOptions(separateExitEnabled: false))
    }

    @Test func separateExitOnlyMatchesWhenEnabledAndActive() {
        let shortcuts = KeyboardShortcuts.defaultGlobalShortcuts
        let options = CursorModeOptions(separateExitEnabled: true)
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 53, modifiers: [], shortcuts: shortcuts, isCursorModeActive: true) == nil)
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 53, modifiers: [], shortcuts: shortcuts, options: options) == nil)
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 53, modifiers: [], shortcuts: shortcuts, isCursorModeActive: true, options: options) == .exitCursorMode)
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 53, modifiers: [.shift], shortcuts: shortcuts, isCursorModeActive: true, options: options) == nil)
    }

    @Test func everyActionIsGatedByEntryMode() {
        let options = CursorModeOptions(separateExitEnabled: true)
        let shortcuts = KeyboardShortcuts.defaultGlobalShortcuts
        for identifier in ShortcutIdentifier.eventTapHandledCases {
            let shortcut = shortcuts[identifier]!
            #expect(GlobalInputEventTap.shortcutIdentifier(for: shortcut.keyCode, modifiers: shortcut.modifiers, shortcuts: shortcuts, options: options) == nil)
            #expect(GlobalInputEventTap.shortcutIdentifier(for: shortcut.keyCode, modifiers: shortcut.modifiers, shortcuts: shortcuts, isCursorModeActive: true, options: options) == identifier)
        }
        #expect(ShortcutIdentifier.carbonHandledCases == [.activateCursorMode])
    }

    @Test func customExitCanBeRecordedAsEscapeOrPlainKey() throws {
        for (code, char) in [(UInt16(53), "\u{1b}"), (UInt16(12), "q")] {
            let button = ShortcutRecorderButton(shortcutIdentifier: .exitCursorMode)
            var captured: KeyboardShortcut?
            button.onCapturedShortcut = { captured = $0 }
            button.beginRecording()
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: char, charactersIgnoringModifiers: char, isARepeat: false, keyCode: code))
            button.capture(event)
            #expect(captured?.keyCode == UInt32(code))
        }
    }

    @Test func customExitRejectsMovementAndClickBindings() {
        let store = ShortcutStore(userDefaults: UserDefaults(suiteName: "ExitTests.\(UUID().uuidString)")!)
        let movement = CursorMovementBindings()
        #expect(store.update(.exitCursorMode, to: movement.left, movementBindings: movement) == .failure(.movementConflict(.left)))
        let enter = KeyboardShortcut(keyCode: 36, modifiers: [], keyEquivalent: "\r", displayKey: "Return")
        #expect(store.update(.exitCursorMode, to: enter) == .failure(.reservedCursorKey))
        let escape = KeyboardShortcuts.defaultGlobalShortcuts[.exitCursorMode]!
        guard case .success = store.update(.exitCursorMode, to: escape) else {
            Issue.record("Escape must be accepted as the exit key")
            return
        }
    }
}
