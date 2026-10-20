import Foundation

enum CursorMovementBindingValidationError: LocalizedError, Equatable {
    case duplicate(CursorMovementDirection)
    case reservedKey
    case unavailable
    case scrollConflict(ShortcutIdentifier)

    var errorDescription: String? {
        switch self {
        case .duplicate(let direction):
            return "That key is already used for \(direction.settingsTitle.lowercased())."
        case .reservedKey:
            return "Return and Escape are reserved while cursor control mode is active."
        case .unavailable:
            return "Cursor movement settings are not available."
        case .scrollConflict(let identifier):
            return "That key is already used for \(identifier.title.lowercased()) in cursor mode."
        }
    }
}

struct CursorMovementBindings: Codable, Equatable {
    var left: KeyboardShortcut
    var down: KeyboardShortcut
    var up: KeyboardShortcut
    var right: KeyboardShortcut

    init(
        left: KeyboardShortcut = KeyboardShortcuts.defaultCursorMovementBindings.left,
        down: KeyboardShortcut = KeyboardShortcuts.defaultCursorMovementBindings.down,
        up: KeyboardShortcut = KeyboardShortcuts.defaultCursorMovementBindings.up,
        right: KeyboardShortcut = KeyboardShortcuts.defaultCursorMovementBindings.right
    ) {
        self.left = left
        self.down = down
        self.up = up
        self.right = right
    }

    subscript(direction: CursorMovementDirection) -> KeyboardShortcut {
        get {
            switch direction {
            case .left:
                return left
            case .down:
                return down
            case .up:
                return up
            case .right:
                return right
            }
        }
        set {
            switch direction {
            case .left:
                left = newValue
            case .down:
                down = newValue
            case .up:
                up = newValue
            case .right:
                right = newValue
            }
        }
    }

    func direction(
        for keyCode: UInt32,
        modifiers: ShortcutModifiers
    ) -> CursorMovementDirection? {
        for direction in CursorMovementDirection.allCases
        where self[direction].keyCode == keyCode && self[direction].modifiers == modifiers {
            return direction
        }

        return nil
    }

    func dragDirection(
        for keyCode: UInt32,
        modifiers: ShortcutModifiers
    ) -> CursorMovementDirection? {
        guard modifiers.contains(AppConstants.cursorDragModifier) else {
            return nil
        }

        let movementModifiers = modifiers.subtracting(AppConstants.cursorDragModifier)
        return direction(for: keyCode, modifiers: movementModifiers)
    }
}

final class CursorMovementBindingStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "CursorControl.CursorMovementBindings.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> CursorMovementBindings {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(CursorMovementBindings.self, from: data) else {
            let defaults = CursorMovementBindings()
            save(defaults)
            return defaults
        }

        return decoded
    }

    func shortcut(for direction: CursorMovementDirection) -> KeyboardShortcut {
        load()[direction]
    }

    func update(
        _ direction: CursorMovementDirection,
        to shortcut: KeyboardShortcut,
        shortcuts: [ShortcutIdentifier: KeyboardShortcut] = [:]
    ) -> Result<CursorMovementBindings, CursorMovementBindingValidationError> {
        var bindings = load()
        let validation = validate(shortcut, for: direction, in: bindings, shortcuts: shortcuts)

        switch validation {
        case .success:
            bindings[direction] = shortcut
            save(bindings)
            return .success(bindings)
        case .failure(let error):
            return .failure(error)
        }
    }

    func restoreDefaults() -> CursorMovementBindings {
        let bindings = CursorMovementBindings()
        save(bindings)
        return bindings
    }

    func save(_ bindings: CursorMovementBindings) {
        guard let data = try? JSONEncoder().encode(bindings) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    func validate(
        _ shortcut: KeyboardShortcut,
        for direction: CursorMovementDirection,
        in bindings: CursorMovementBindings? = nil,
        shortcuts: [ShortcutIdentifier: KeyboardShortcut] = [:]
    ) -> Result<Void, CursorMovementBindingValidationError> {
        guard shortcut.keyCode != UInt32(KeyboardShortcuts.escapeKeyCode),
              !KeyboardShortcuts.returnKeyCodes.contains(UInt16(shortcut.keyCode)) else {
            return .failure(.reservedKey)
        }

        for (identifier, scrollShortcut) in shortcuts
        where identifier.requiresCursorMode(for: scrollShortcut) && scrollShortcut.keyCode == shortcut.keyCode {
            if scrollShortcut.modifiers == shortcut.modifiers
                || scrollShortcut.modifiers == shortcut.modifiers.union(AppConstants.cursorDragModifier) {
                return .failure(.scrollConflict(identifier))
            }
        }

        let activeBindings = bindings ?? load()
        for existingDirection in CursorMovementDirection.allCases
        where existingDirection != direction && activeBindings[existingDirection] == shortcut {
            return .failure(.duplicate(existingDirection))
        }

        return .success(())
    }
}

extension CursorMovementDirection {
    var settingsTitle: String {
        switch self {
        case .left:
            return "Move left"
        case .down:
            return "Move down"
        case .up:
            return "Move up"
        case .right:
            return "Move right"
        }
    }

    var settingsDescription: String {
        switch self {
        case .left:
            return "Moves the cursor left while cursor control mode is active."
        case .down:
            return "Moves the cursor down while cursor control mode is active."
        case .up:
            return "Moves the cursor up while cursor control mode is active."
        case .right:
            return "Moves the cursor right while cursor control mode is active."
        }
    }
}
