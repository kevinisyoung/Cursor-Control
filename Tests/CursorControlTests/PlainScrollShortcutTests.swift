import AppKit
import Testing
@testable import CursorControl

@MainActor
struct PlainScrollShortcutTests {
    private func store() -> ShortcutStore {
        ShortcutStore(userDefaults: UserDefaults(suiteName: "PlainScrollTests.\(UUID().uuidString)")!)
    }

    private let arrow = KeyboardShortcut(keyCode: 126, modifiers: [], keyEquivalent: "\u{f700}", displayKey: "Up Arrow")

    @Test func plainScrollIsAcceptedAndPersisted() {
        let store = store()
        guard case .success = store.update(.scrollUp, to: arrow, movementBindings: CursorMovementBindings()) else {
            Issue.record("Plain scroll should be accepted")
            return
        }
        #expect(store.shortcut(for: .scrollUp) == arrow)
    }

    @Test func plainScrollOnlyMatchesInCursorMode() {
        let shortcuts: [ShortcutIdentifier: KeyboardShortcut] = [.scrollUp: arrow]
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 126, modifiers: [], shortcuts: shortcuts) == nil)
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 126, modifiers: [], shortcuts: shortcuts, isCursorModeActive: true) == .scrollUp)
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 126, modifiers: [.control], shortcuts: shortcuts, isCursorModeActive: true) == nil)
    }

    @Test func modifiedScrollStaysGlobal() {
        let shortcuts = KeyboardShortcuts.defaultGlobalShortcuts
        #expect(GlobalInputEventTap.shortcutIdentifier(for: 4, modifiers: [.control], shortcuts: shortcuts) == .scrollLeft)
    }

    @Test func plainKeysRemainUnavailableForOtherGlobalActions() {
        for identifier in [ShortcutIdentifier.activateCursorMode, .autoClicker, .middleClick, .mouseJiggler] {
            #expect(store().update(identifier, to: arrow) == .failure(.missingPrimaryModifier))
        }
    }

    @Test func scrollRejectsMovementAndReservedKeys() {
        let movement = CursorMovementBindings()
        #expect(store().update(.scrollUp, to: movement.up, movementBindings: movement) == .failure(.movementConflict(.up)))
        let drag = KeyboardShortcut(keyCode: movement.up.keyCode, modifiers: [.shift], keyEquivalent: "k", displayKey: "K")
        #expect(store().update(.scrollUp, to: drag, movementBindings: movement) == .failure(.movementConflict(.up)))
        for code: UInt32 in [36, 53, 76] {
            let key = KeyboardShortcut(keyCode: code, modifiers: [], keyEquivalent: "x", displayKey: "X")
            #expect(store().update(.scrollUp, to: key) == .failure(.reservedCursorKey))
        }
    }

    @Test func movementRejectsAnExistingPlainScrollBinding() {
        let defaults = UserDefaults(suiteName: "PlainScrollMovementTests.\(UUID().uuidString)")!
        let movement = CursorMovementBindingStore(userDefaults: defaults)
        #expect(movement.update(.up, to: arrow, shortcuts: [.scrollUp: arrow]) == .failure(.scrollConflict(.scrollUp)))
    }

    @Test func recorderCapturesPlainArrowAndSlash() throws {
        for (keyCode, character, name) in [(UInt16(126), "\u{f700}", "Up Arrow"), (UInt16(44), "/", "/")] {
            let button = ShortcutRecorderButton(shortcutIdentifier: .scrollUp)
            var captured: KeyboardShortcut?
            button.onCapturedShortcut = { captured = $0 }
            button.beginRecording()
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
            button.capture(event)
            #expect(captured?.keyCode == UInt32(keyCode))
            #expect(captured?.modifiers.isEmpty == true)
            #expect(captured?.displayName == name)
        }
    }
}
