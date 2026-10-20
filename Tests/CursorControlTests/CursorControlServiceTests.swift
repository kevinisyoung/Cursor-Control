import CoreGraphics
import Foundation
import Testing
@testable import CursorControl

@MainActor
struct CursorControlServiceTests {
    private let clickLocation = CGPoint(x: 300, y: 220)

    @Test func successfulClickKeepsCursorControlActive() {
        let mouseClickService = SpyMouseClickService()
        let service = makeService(mouseClickService: mouseClickService)
        var activeStateChanges: [Bool] = []
        service.onActiveStateChanged = { activeStateChanges.append($0) }

        service.start()
        service.handle(.leftClick)

        #expect(service.isActive)
        #expect(service.captureMode == .movement)
        #expect(mouseClickService.clicks == [MouseClickRecord(kind: .left, point: clickLocation)])
        #expect(activeStateChanges == [true])
    }

    @Test func failedClickKeepsCursorControlActive() {
        let mouseClickService = SpyMouseClickService()
        mouseClickService.shouldSucceed = false
        let alert = FakeAccessibilityAlert()
        let service = makeService(
            alert: alert,
            mouseClickService: mouseClickService
        )

        service.start()
        service.handle(.leftClick)

        #expect(service.isActive)
        #expect(service.captureMode == .movement)
        #expect(alert.clickFailureCount == 1)
    }

    @Test func quickSecondLeftClickPostsDoubleClick() {
        let mouseClickService = SpyMouseClickService()
        var now = Date(timeIntervalSince1970: 1_000)
        let service = makeService(
            mouseClickService: mouseClickService,
            dateProvider: { now },
            doubleClickInterval: 0.5
        )

        service.start()
        service.handle(.leftClick)
        now = now.addingTimeInterval(0.2)
        service.handle(.leftClick)

        #expect(
            mouseClickService.clicks == [
                MouseClickRecord(kind: .left, point: clickLocation),
                MouseClickRecord(kind: .doubleLeft, point: clickLocation)
            ]
        )
    }

    @Test func slowSecondLeftClickPostsSingleClick() {
        let mouseClickService = SpyMouseClickService()
        var now = Date(timeIntervalSince1970: 1_000)
        let service = makeService(
            mouseClickService: mouseClickService,
            dateProvider: { now },
            doubleClickInterval: 0.5
        )

        service.start()
        service.handle(.leftClick)
        now = now.addingTimeInterval(0.7)
        service.handle(.leftClick)

        #expect(
            mouseClickService.clicks == [
                MouseClickRecord(kind: .left, point: clickLocation),
                MouseClickRecord(kind: .left, point: clickLocation)
            ]
        )
    }

    @Test func rightClickPostsRightClickWithoutExiting() {
        let mouseClickService = SpyMouseClickService()
        let service = makeService(mouseClickService: mouseClickService)

        service.start()
        service.handle(.rightClick)

        #expect(service.isActive)
        #expect(mouseClickService.clicks == [MouseClickRecord(kind: .right, point: clickLocation)])
    }

    @Test func successfulMovementReportsMovedCursorPoint() {
        let cursorPositionService = FakeCursorPositionService(
            currentLocation: clickLocation,
            currentDisplayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800)
        )
        let service = makeService(cursorPositionService: cursorPositionService)
        var movedPoints: [CGPoint] = []
        service.onCursorMoved = { movedPoints.append($0) }

        service.start()
        service.handle(.movementKeyDown(.right))

        #expect(movedPoints == cursorPositionService.movedPoints)
        #expect(movedPoints.count == 1)
        #expect(movedPoints.first?.x ?? 0 > clickLocation.x)
    }

    @Test func shiftDragHoldKeepsLeftMouseDownAcrossMovementBursts() {
        let mouseClickService = SpyMouseClickService()
        let service = makeService(mouseClickService: mouseClickService)

        service.start()
        service.handle(.dragHoldChanged(true))
        service.handle(.movementKeyDown(.right))
        service.handle(.movementKeyUp(.right))

        #expect(mouseClickService.dragEvents.count == 2)
        #expect(service.isActive)

        service.handle(.movementKeyDown(.down))
        service.handle(.movementKeyUp(.down))
        service.handle(.dragHoldChanged(false))

        guard case let .beganDrag(startPoint) = mouseClickService.dragEvents.first,
              case let .dragged(dragPoint) = mouseClickService.dragEvents.dropFirst().first,
              case let .dragged(secondDragPoint) = mouseClickService.dragEvents.dropFirst(2).first,
              case let .endedDrag(endPoint) = mouseClickService.dragEvents.dropFirst(3).first else {
            Issue.record("Expected a complete drag sequence")
            return
        }

        #expect(startPoint == clickLocation)
        #expect(dragPoint.x > clickLocation.x)
        #expect(secondDragPoint.y > dragPoint.y)
        #expect(endPoint == secondDragPoint)
        #expect(service.isActive)
    }

    private func makeService(
        permission: FakeAccessibilityPermission = FakeAccessibilityPermission(isTrusted: true),
        alert: FakeAccessibilityAlert = FakeAccessibilityAlert(),
        cursorPositionService: FakeCursorPositionService? = nil,
        mouseClickService: SpyMouseClickService = SpyMouseClickService(),
        dateProvider: @escaping () -> Date = Date.init,
        doubleClickInterval: TimeInterval = 0.5
    ) -> CursorControlService {
        CursorControlService(
            permissionService: permission,
            permissionAlert: alert,
            cursorPositionService: cursorPositionService ?? FakeCursorPositionService(
                currentLocation: clickLocation,
                currentDisplayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800)
            ),
            mouseClickService: mouseClickService,
            dateProvider: dateProvider,
            doubleClickInterval: doubleClickInterval
        )
    }
}

private final class FakeAccessibilityPermission: AccessibilityPermissionProviding {
    var isTrusted: Bool
    private(set) var requestPromptCount = 0
    private(set) var openSettingsCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestSystemPrompt() {
        requestPromptCount += 1
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

@MainActor
private final class FakeAccessibilityAlert: AccessibilityPermissionAlerting {
    private(set) var missingPermissionCount = 0
    private(set) var clickFailureCount = 0

    func presentMissingPermission() -> Bool {
        missingPermissionCount += 1
        return false
    }

    func presentClickFailure() {
        clickFailureCount += 1
    }
}

private final class FakeCursorPositionService: CursorPositionProviding {
    var currentLocation: CGPoint?
    var currentDisplayBounds: CGRect?
    private(set) var movedPoints: [CGPoint] = []

    init(currentLocation: CGPoint?, currentDisplayBounds: CGRect?) {
        self.currentLocation = currentLocation
        self.currentDisplayBounds = currentDisplayBounds
    }

    func moveCursor(to point: CGPoint) -> Bool {
        movedPoints.append(point)
        currentLocation = point
        return true
    }
}

private struct MouseClickRecord: Equatable {
    let kind: MouseClickKind
    let point: CGPoint
}

private enum MouseDragRecord: Equatable {
    case beganDrag(CGPoint)
    case dragged(CGPoint)
    case endedDrag(CGPoint)
}

private final class SpyMouseClickService: MouseClicking {
    var shouldSucceed = true
    private(set) var clicks: [MouseClickRecord] = []
    private(set) var dragEvents: [MouseDragRecord] = []

    func click(_ kind: MouseClickKind, at point: CGPoint) -> Bool {
        clicks.append(MouseClickRecord(kind: kind, point: point))
        return shouldSucceed
    }

    func fastLeftClick(at point: CGPoint) -> Bool {
        click(.left, at: point)
    }

    func beginLeftDrag(at point: CGPoint) -> Bool {
        dragEvents.append(.beganDrag(point))
        return shouldSucceed
    }

    func dragLeftMouse(to point: CGPoint) -> Bool {
        dragEvents.append(.dragged(point))
        return shouldSucceed
    }

    func endLeftDrag(at point: CGPoint) -> Bool {
        dragEvents.append(.endedDrag(point))
        return shouldSucceed
    }
}
