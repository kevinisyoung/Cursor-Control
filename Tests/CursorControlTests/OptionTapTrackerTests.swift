import CoreGraphics
import Testing
@testable import CursorControl

struct OptionTapTrackerTests {
    private let leftDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    private let rightDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)

    @Test func recognizesEachSideOnReleaseOnly() {
        for (key, flags) in [(UInt32(58), leftDown), (UInt32(61), rightDown)] {
            var tracker = OptionTapTracker()
            #expect(tracker.handle(type: .flagsChanged, keyCode: key, flags: flags, timestamp: 1) == nil)
            #expect(tracker.handle(type: .flagsChanged, keyCode: key, flags: [], timestamp: 1.1)
                == KeyboardShortcut.optionTap(keyCode: key))
            #expect(tracker.handle(type: .flagsChanged, keyCode: key, flags: [], timestamp: 1.2) == nil)
        }
        #expect(KeyboardShortcut.optionTap(keyCode: 58) != KeyboardShortcut.optionTap(keyCode: 61))
    }

    @Test func ignoresLongHoldsAndOrphanReleases() {
        var tracker = OptionTapTracker()
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 1) == nil)
        _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 2)
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 2.5) == nil)
    }

    @Test func chordsAndClicksCancelTap() {
        for eventType in [CGEventType.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel] {
            var tracker = OptionTapTracker()
            _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 1)
            _ = tracker.handle(type: eventType, keyCode: 0, flags: rightDown, timestamp: 1.05)
            #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 1.1) == nil)
        }
    }

    @Test func otherModifiersCancelTapInEitherOrder() {
        var tracker = OptionTapTracker()
        _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown.union(.maskShift), timestamp: 1)
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 1.1) == nil)
        _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 2)
        _ = tracker.handle(type: .flagsChanged, keyCode: 56, flags: rightDown.union(.maskShift), timestamp: 2.05)
        _ = tracker.handle(type: .flagsChanged, keyCode: 56, flags: rightDown, timestamp: 2.1)
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 2.15) == nil)
    }

    @Test func bothOptionKeysDoNotToggle() {
        var tracker = OptionTapTracker()
        let both = leftDown.union(rightDown)
        _ = tracker.handle(type: .flagsChanged, keyCode: 58, flags: leftDown, timestamp: 1)
        _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: both, timestamp: 1.02)
        #expect(tracker.handle(type: .flagsChanged, keyCode: 58, flags: rightDown, timestamp: 1.04) == nil)
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 1.06) == nil)
    }

    @Test func keysAndMouseButtonsHeldBeforeOptionCancelTap() {
        for (down, up) in [(CGEventType.keyDown, CGEventType.keyUp), (.leftMouseDown, .leftMouseUp)] {
            var tracker = OptionTapTracker()
            _ = tracker.handle(type: down, keyCode: 0, flags: [], timestamp: 0.9)
            _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 1)
            #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 1.1) == nil)
            _ = tracker.handle(type: up, keyCode: 0, flags: [], timestamp: 1.2)
            _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 2)
            #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 2.1) != nil)
        }
    }

    @Test func resetDiscardsPendingTapAndNextTapWorks() {
        var tracker = OptionTapTracker()
        _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 1)
        tracker.reset()
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 1.1) == nil)
        _ = tracker.handle(type: .flagsChanged, keyCode: 61, flags: rightDown, timestamp: 2)
        #expect(tracker.handle(type: .flagsChanged, keyCode: 61, flags: [], timestamp: 2.1) != nil)
    }
}
