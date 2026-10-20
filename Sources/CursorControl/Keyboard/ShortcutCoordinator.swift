import AppKit
import OSLog

enum ShortcutUpdateResult: Equatable {
    case success
    case validationFailure(String)
    case registrationFailure(String)
}

@MainActor
final class ShortcutCoordinator {
    private let modeOptionsStore = CursorModeOptionsStore()
    private let store: ShortcutStore
    private let service: GlobalShortcutService
    private let inputEventTap: GlobalInputEventTap
    private let logger = Logger(
        subsystem: AppConstants.bundleIdentifier,
        category: "ShortcutCoordinator"
    )
    private var handlers: [ShortcutIdentifier: @MainActor (CGEventType, Int) -> Void] = [:]
    private var onCursorInput: (CursorControlInput) -> Void = { _ in }
    private var onInputTapDisabled: () -> Void = {}
    private var isCursorModeActive = false
    private var cursorCaptureMode: CursorControlCaptureMode = .movement
    private var cursorMovementBindings = CursorMovementBindings()

    init(
        store: ShortcutStore = ShortcutStore(),
        service: GlobalShortcutService = GlobalShortcutService(),
        inputEventTap: GlobalInputEventTap = GlobalInputEventTap()
    ) {
        self.store = store
        self.service = service
        self.inputEventTap = inputEventTap
    }

    func start(
        handlers: [ShortcutIdentifier: @MainActor (CGEventType, Int) -> Void],
        cursorMovementBindings: CursorMovementBindings,
        onCursorInput: @escaping (CursorControlInput) -> Void,
        onInputTapDisabled: @escaping () -> Void
    ) -> ShortcutUpdateResult {
        self.handlers = handlers
        self.cursorMovementBindings = cursorMovementBindings
        self.onCursorInput = onCursorInput
        self.onInputTapDisabled = onInputTapDisabled
        return applyCurrentAssignments()
    }

    func shortcut(for identifier: ShortcutIdentifier) -> KeyboardShortcut {
        store.shortcut(for: identifier)
    }

    var modeOptions: CursorModeOptions { modeOptionsStore.load() }

    func updateModeOptions(_ options: CursorModeOptions) {
        modeOptionsStore.save(options)
        inputEventTap.setModeOptions(options)
    }

    var currentShortcuts: [ShortcutIdentifier: KeyboardShortcut] { store.load().all }

    func updateShortcut(
        _ identifier: ShortcutIdentifier,
        to shortcut: KeyboardShortcut
    ) -> ShortcutUpdateResult {
        let previousAssignments = store.load()

        switch store.update(identifier, to: shortcut, movementBindings: cursorMovementBindings) {
        case .success:
            let result = applyCurrentAssignments()
            if case .success = result {
                return .success
            }

            store.replace(with: previousAssignments)
            _ = applyCurrentAssignments()
            return result
        case .failure(let error):
            return .validationFailure(error.localizedDescription)
        }
    }

    func restoreDefaults() -> ShortcutUpdateResult {
        let previousAssignments = store.load()
        _ = store.restoreDefaults()

        let result = applyCurrentAssignments()
        if case .success = result {
            return .success
        }

        store.replace(with: previousAssignments)
        _ = applyCurrentAssignments()
        return result
    }

    func suspendRegistrations() {
        service.unregisterAll()
        inputEventTap.stop()
    }

    @discardableResult
    func resumeRegistrations() -> ShortcutUpdateResult {
        applyCurrentAssignments()
    }

    func unregisterAll() {
        service.unregisterAll()
        inputEventTap.stop()
    }

    func setCursorModeActive(_ isActive: Bool) {
        isCursorModeActive = isActive
        cursorCaptureMode = .movement
        inputEventTap.setCursorModeActive(isActive, captureMode: .movement)
    }

    func setCursorCaptureMode(_ captureMode: CursorControlCaptureMode) {
        cursorCaptureMode = captureMode
        inputEventTap.setCursorCaptureMode(captureMode)
    }

    func updateCursorMovementBindings(_ bindings: CursorMovementBindings) {
        cursorMovementBindings = bindings
        inputEventTap.setCursorMovementBindings(bindings)
    }

    private func applyCurrentAssignments() -> ShortcutUpdateResult {
        let assignments = store.load().all
        let result = service.registerShortcuts(assignments) { [weak self] identifier in
            self?.handleShortcut(identifier, type: .keyDown, repeatCount: 0)
        }

        switch result {
        case .success:
            break
        case .failure(let failure):
            logger.error("\(failure.message)")
            return .registrationFailure(failure.message)
        }

        if !inputEventTap.start(
            shortcuts: assignments,
            cursorMovementBindings: cursorMovementBindings,
            onShortcut: { [weak self] identifier, type, repeatCount in
                self?.handleShortcut(identifier, type: type, repeatCount: repeatCount)
            },
            onCursorInput: { [weak self] input in
                self?.onCursorInput(input)
            },
            onTapDisabled: { [weak self] in
                self?.onInputTapDisabled()
            }
        ) {
            logger.error("Global input event tap was unavailable; scroll shortcuts may not work until Accessibility permission is granted.")
        }
        inputEventTap.setModeOptions(modeOptionsStore.load())
        inputEventTap.setCursorModeActive(
            isCursorModeActive,
            captureMode: cursorCaptureMode
        )

        return .success
    }

    private func handleShortcut(_ identifier: ShortcutIdentifier, type: CGEventType, repeatCount: Int) {
        handlers[identifier]?(type, repeatCount)
    }
}
