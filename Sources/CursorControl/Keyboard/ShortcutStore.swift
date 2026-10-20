import Foundation

enum ShortcutValidationError: LocalizedError, Equatable {
    case duplicate(ShortcutIdentifier)
    case missingPrimaryModifier

    var errorDescription: String? {
        switch self {
        case .duplicate(let existingIdentifier):
            return "That shortcut is already used by \(existingIdentifier.title)."
        case .missingPrimaryModifier:
            return "Use Command, Control, or Option with the shortcut."
        }
    }
}

struct ShortcutAssignments: Codable, Equatable {
    private var shortcuts: [ShortcutIdentifier: KeyboardShortcut]

    init(shortcuts: [ShortcutIdentifier: KeyboardShortcut] = KeyboardShortcuts.defaultGlobalShortcuts) {
        self.shortcuts = shortcuts
    }

    subscript(identifier: ShortcutIdentifier) -> KeyboardShortcut {
        get { shortcuts[identifier] ?? KeyboardShortcuts.defaultGlobalShortcuts[identifier]! }
        set { shortcuts[identifier] = newValue }
    }

    var all: [ShortcutIdentifier: KeyboardShortcut] {
        var result = KeyboardShortcuts.defaultGlobalShortcuts
        for (identifier, shortcut) in shortcuts {
            result[identifier] = shortcut
        }
        return result
    }
}

final class ShortcutStore {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let legacyStorageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "CursorControl.GlobalShortcuts.v4",
        legacyStorageKey: String = "CursorControl.GlobalShortcuts.v3"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.legacyStorageKey = legacyStorageKey
    }

    func load() -> ShortcutAssignments {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ShortcutAssignments.self, from: data) else {
            let migratedAssignments = migratedLegacyAssignments()
            save(migratedAssignments)
            return migratedAssignments
        }

        return decoded
    }

    func shortcut(for identifier: ShortcutIdentifier) -> KeyboardShortcut {
        load()[identifier]
    }

    func save(_ assignments: ShortcutAssignments) {
        guard let data = try? JSONEncoder().encode(assignments) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    func update(
        _ identifier: ShortcutIdentifier,
        to shortcut: KeyboardShortcut
    ) -> Result<ShortcutAssignments, ShortcutValidationError> {
        var assignments = load()
        let validation = validate(shortcut, for: identifier, in: assignments)

        switch validation {
        case .success:
            assignments[identifier] = shortcut
            save(assignments)
            return .success(assignments)
        case .failure(let error):
            return .failure(error)
        }
    }

    func restoreDefaults() -> ShortcutAssignments {
        let assignments = ShortcutAssignments()
        save(assignments)
        return assignments
    }

    func replace(with assignments: ShortcutAssignments) {
        save(assignments)
    }

    func validate(
        _ shortcut: KeyboardShortcut,
        for identifier: ShortcutIdentifier,
        in assignments: ShortcutAssignments? = nil
    ) -> Result<Void, ShortcutValidationError> {
        guard (identifier == .activateCursorMode && shortcut.isOptionTap)
            || !shortcut.modifiers.intersection([.command, .control, .option]).isEmpty else {
            return .failure(.missingPrimaryModifier)
        }

        let activeAssignments = assignments ?? load()
        for (existingIdentifier, existingShortcut) in activeAssignments.all
        where existingIdentifier != identifier && existingShortcut == shortcut {
            return .failure(.duplicate(existingIdentifier))
        }

        return .success(())
    }

    private func migratedLegacyAssignments() -> ShortcutAssignments {
        guard let data = userDefaults.data(forKey: legacyStorageKey),
              let decoded = try? JSONDecoder().decode(LegacyShortcutAssignments.self, from: data) else {
            return ShortcutAssignments()
        }

        var shortcuts = KeyboardShortcuts.defaultGlobalShortcuts
        for (identifier, shortcut) in decoded.all {
            switch identifier {
            case .activateCursorMode:
                shortcuts[.activateCursorMode] = shortcut
            case .scrollLeft:
                shortcuts[.scrollLeft] = shortcut
            case .scrollDown:
                shortcuts[.scrollDown] = shortcut
            case .scrollUp:
                shortcuts[.scrollUp] = shortcut
            case .scrollRight:
                shortcuts[.scrollRight] = shortcut
            case .activateOverlay:
                continue
            }
        }

        return ShortcutAssignments(shortcuts: shortcuts)
    }
}

private enum LegacyShortcutIdentifier: String, Codable, Hashable {
    case activateOverlay
    case activateCursorMode
    case scrollLeft
    case scrollDown
    case scrollUp
    case scrollRight
}

private struct LegacyShortcutAssignments: Codable {
    private var shortcuts: [LegacyShortcutIdentifier: KeyboardShortcut]

    var all: [LegacyShortcutIdentifier: KeyboardShortcut] {
        shortcuts
    }
}
