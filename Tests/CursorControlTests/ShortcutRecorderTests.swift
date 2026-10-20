import AppKit
import Testing
@testable import CursorControl

@MainActor
struct ShortcutRecorderTests {
    @Test func recorderCapturesRightOptionOnRelease() throws {
        let button = ShortcutRecorderButton(shortcutIdentifier: .activateCursorMode)
        var captured: KeyboardShortcut?
        button.onCapturedShortcut = { captured = $0 }
        button.beginRecording()
        button.capture(try optionEvent(isDown: true, timestamp: 1))
        #expect(captured == nil)
        button.capture(try optionEvent(isDown: false, timestamp: 1.1))
        #expect(captured == KeyboardShortcut.optionTap(keyCode: 61))
    }

    @Test func recorderDoesNotOfferOptionTapForScrolling() throws {
        let button = ShortcutRecorderButton(shortcutIdentifier: .scrollLeft)
        var captured: KeyboardShortcut?
        button.onCapturedShortcut = { captured = $0 }
        button.beginRecording()
        button.capture(try optionEvent(isDown: true, timestamp: 1))
        button.capture(try optionEvent(isDown: false, timestamp: 1.1))
        #expect(captured == nil)
    }

    @Test func cancellingRecordingDiscardsPendingTap() throws {
        let button = ShortcutRecorderButton(shortcutIdentifier: .activateCursorMode)
        var captured: KeyboardShortcut?
        button.onCapturedShortcut = { captured = $0 }
        button.beginRecording()
        button.capture(try optionEvent(isDown: true, timestamp: 1))
        button.cancelRecording()
        button.beginRecording()
        button.capture(try optionEvent(isDown: false, timestamp: 1.1))
        #expect(captured == nil)
    }

    private func optionEvent(isDown: Bool, timestamp: Double) throws -> NSEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: isDown))
        event.type = .flagsChanged
        event.flags = isDown ? CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40) : []
        event.timestamp = UInt64(timestamp * 1_000_000_000)
        return try #require(NSEvent(cgEvent: event))
    }
}
