import AppKit
import Carbon
import OSLog

private let vimClickHotKeySignature: OSType = 0x56434C4B // "VCLK"

private func globalShortcutEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event,
          let context,
          let hotKeyID = hotKeyID(from: event),
          hotKeyID.signature == vimClickHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let service = Unmanaged<GlobalShortcutService>
        .fromOpaque(context)
        .takeUnretainedValue()

    return MainActor.assumeIsolated {
        service.handleHotKey(id: hotKeyID.id)
        return noErr
    }
}

private func hotKeyID(from event: EventRef) -> EventHotKeyID? {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    return status == noErr ? hotKeyID : nil
}

struct GlobalShortcutRegistrationFailure: Error, Equatable {
    let identifier: ShortcutIdentifier
    let shortcut: KeyboardShortcut
    let status: OSStatus

    var message: String {
        "Could not register \(identifier.title) (\(shortcut.displayName)). macOS returned \(status)."
    }
}

@MainActor
final class GlobalShortcutService {
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [ShortcutIdentifier: EventHotKeyRef] = [:]
    private var onShortcut: ((ShortcutIdentifier) -> Void)?
    private var identifiersByHotKeyID: [UInt32: ShortcutIdentifier] = [:]
    private let logger = Logger(
        subsystem: AppConstants.bundleIdentifier,
        category: "GlobalShortcut"
    )

    @discardableResult
    func registerShortcuts(
        _ shortcuts: [ShortcutIdentifier: KeyboardShortcut],
        onShortcut: @escaping @MainActor (ShortcutIdentifier) -> Void
    ) -> Result<Void, GlobalShortcutRegistrationFailure> {
        unregisterAll()
        self.onShortcut = onShortcut

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalShortcutEventHandler,
            1,
            &eventType,
            context,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            logger.error("Could not install hotkey handler: \(handlerStatus)")
            unregisterAll()
            let fallbackShortcut = KeyboardShortcuts.defaultGlobalShortcuts[.activateCursorMode]!
            return .failure(
                GlobalShortcutRegistrationFailure(
                    identifier: .activateCursorMode,
                    shortcut: fallbackShortcut,
                    status: handlerStatus
                )
            )
        }

        for identifier in ShortcutIdentifier.carbonHandledCases {
            guard let shortcut = shortcuts[identifier], !shortcut.isOptionTap else {
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: vimClickHotKeySignature,
                id: identifier.hotKeyID
            )
            let registrationStatus = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers.carbonFlags,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            guard registrationStatus == noErr, let hotKeyRef else {
                logger.error(
                    "Could not register \(identifier.title) \(shortcut.displayName): \(registrationStatus)"
                )
                let failure = GlobalShortcutRegistrationFailure(
                    identifier: identifier,
                    shortcut: shortcut,
                    status: registrationStatus
                )
                unregisterAll()
                return .failure(failure)
            }

            registeredHotKeys[identifier] = hotKeyRef
            identifiersByHotKeyID[identifier.hotKeyID] = identifier
            logger.notice("Registered \(identifier.title): \(shortcut.displayName)")
        }

        return .success(())
    }

    func unregisterAll() {
        for hotKey in registeredHotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        registeredHotKeys.removeAll()
        identifiersByHotKeyID.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onShortcut = nil
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let identifier = identifiersByHotKeyID[id] else {
            logger.error("Received unknown hotkey id \(id)")
            return
        }

        logger.notice("Received \(identifier.title)")
        onShortcut?(identifier)
    }
}
