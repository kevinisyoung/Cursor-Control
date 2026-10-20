import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cursorControlService: CursorControlService?
    private var menuBarController: MenuBarController?
    private var onboardingWindowController: OnboardingWindowController?
    private var scrollService: ScrollService?
    private var scrollSettingsStore: ScrollSettingsStore?
    private var cursorSettingsStore: CursorSettingsStore?
    private var cursorMovementBindingStore: CursorMovementBindingStore?
    private var autoClickerSettingsStore: AutoClickerSettingsStore?
    private var mouseClickService: MouseClickService?
    private var autoClickerService: AutoClickerService?
    private var jigglerService: JigglerService?
    private var cursorModeIndicatorController: CursorModeIndicatorController?
    private var settingsWindowController: SettingsWindowController?
    private var shortcutCoordinator: ShortcutCoordinator?
    private let logger = Logger(
        subsystem: AppConstants.bundleIdentifier,
        category: "AppDelegate"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scrollSettingsStore = ScrollSettingsStore()
        self.scrollSettingsStore = scrollSettingsStore
        let scrollService = ScrollService(settingsProvider: { scrollSettingsStore.load() })
        self.scrollService = scrollService
        let cursorSettingsStore = CursorSettingsStore()
        self.cursorSettingsStore = cursorSettingsStore
        let cursorMovementBindingStore = CursorMovementBindingStore()
        self.cursorMovementBindingStore = cursorMovementBindingStore
        let autoClickerSettingsStore = AutoClickerSettingsStore()
        self.autoClickerSettingsStore = autoClickerSettingsStore
        let mouseClickService = MouseClickService()
        self.mouseClickService = mouseClickService
        let autoClickerService = AutoClickerService(
            settingsProvider: { autoClickerSettingsStore.load() },
            mouseClickService: mouseClickService
        )
        self.autoClickerService = autoClickerService
        let jigglerService = JigglerService()
        self.jigglerService = jigglerService
        let cursorControlService = CursorControlService(
            settingsProvider: { cursorSettingsStore.load() }
        )
        self.cursorControlService = cursorControlService
        let cursorModeIndicatorController = CursorModeIndicatorController(
            settingsProvider: { cursorSettingsStore.load() }
        )
        self.cursorModeIndicatorController = cursorModeIndicatorController

        let shortcutCoordinator = ShortcutCoordinator()
        self.shortcutCoordinator = shortcutCoordinator

        let onboardingWindowController = OnboardingWindowController()
        self.onboardingWindowController = onboardingWindowController

        let menuBarController = MenuBarController(
            cursorModeShortcut: shortcutCoordinator.shortcut(for: .activateCursorMode),
            onToggleCursorMode: { [weak cursorControlService] in
                cursorControlService?.toggle()
            },
            onShowGuide: { [weak onboardingWindowController] in
                onboardingWindowController?.show()
            },
            onOpenSettings: { [weak self] in
                self?.settingsWindowController?.show()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        self.menuBarController = menuBarController

        jigglerService.onActiveStateChanged = { [weak self] isActive in
            self?.menuBarController?.setJigglerActive(isActive)
        }

        cursorControlService.onActiveStateChanged = {
            [weak self, weak menuBarController, weak shortcutCoordinator, weak cursorModeIndicatorController] isActive in
            shortcutCoordinator?.setCursorModeActive(isActive)
            menuBarController?.setCursorModeActive(isActive)
            self?.settingsWindowController?.setCursorModeActive(isActive)
            if isActive {
                cursorModeIndicatorController?.show()
            } else {
                cursorModeIndicatorController?.hide()
                self?.autoClickerService?.stop()
                self?.jigglerService?.stop()
            }
        }
        cursorControlService.onCaptureModeChanged = { [weak shortcutCoordinator] captureMode in
            shortcutCoordinator?.setCursorCaptureMode(captureMode)
        }
        cursorControlService.onCursorMoved = { [weak cursorModeIndicatorController] point in
            cursorModeIndicatorController?.update(toQuartzCursorLocation: point)
        }

        let settingsWindowController = SettingsWindowController(
            autoClickerSettingsProvider: { [weak autoClickerSettingsStore] in
                autoClickerSettingsStore?.load() ?? AutoClickerSettings()
            },
            onAutoClickerSettingsChange: { [weak autoClickerSettingsStore] settings in
                autoClickerSettingsStore?.save(settings)
            },
            onRestoreAutoClickerSettingsDefaults: { [weak autoClickerSettingsStore] in
                autoClickerSettingsStore?.restoreDefaults() ?? AutoClickerSettings()
            },
            onToggleCursorMode: { [weak cursorControlService] in
                cursorControlService?.toggle()
                return cursorControlService?.isActive ?? false
            },
            modeOptionsProvider: { [weak shortcutCoordinator] in
                shortcutCoordinator?.modeOptions ?? CursorModeOptions()
            },
            onModeOptionsChange: { [weak shortcutCoordinator] options in
                shortcutCoordinator?.updateModeOptions(options)
            },
            shortcutProvider: { [weak shortcutCoordinator] identifier in
                shortcutCoordinator?.shortcut(for: identifier)
                    ?? KeyboardShortcuts.defaultGlobalShortcuts[identifier]!
            },
            scrollSettingsProvider: { [weak scrollSettingsStore] in
                scrollSettingsStore?.load() ?? ScrollSettings()
            },
            cursorSettingsProvider: { [weak cursorSettingsStore] in
                cursorSettingsStore?.load() ?? CursorSettings()
            },
            cursorMovementBindingProvider: { [weak cursorMovementBindingStore] direction in
                cursorMovementBindingStore?.shortcut(for: direction)
                    ?? CursorMovementBindings()[direction]
            },
            onShortcutChange: { [weak shortcutCoordinator, weak menuBarController] identifier, shortcut in
                guard let shortcutCoordinator else {
                    return .registrationFailure("Shortcut services are not available.")
                }

                let result = shortcutCoordinator.updateShortcut(identifier, to: shortcut)
                if case .success = result, identifier == .activateCursorMode {
                    menuBarController?.updateCursorModeShortcut(shortcut)
                }
                return result
            },
            onRestoreDefaults: { [weak shortcutCoordinator, weak menuBarController] in
                guard let shortcutCoordinator else {
                    return .registrationFailure("Shortcut services are not available.")
                }

                let result = shortcutCoordinator.restoreDefaults()
                if case .success = result {
                    menuBarController?.updateCursorModeShortcut(
                        shortcutCoordinator.shortcut(for: .activateCursorMode)
                    )
                }
                return result
            },
            onScrollSettingsChange: { [weak scrollSettingsStore] settings in
                scrollSettingsStore?.save(settings)
            },
            onRestoreScrollSettingsDefaults: { [weak scrollSettingsStore] in
                scrollSettingsStore?.restoreDefaults() ?? ScrollSettings()
            },
            onCursorSettingsChange: { [weak cursorSettingsStore] settings in
                cursorSettingsStore?.save(settings)
            },
            onRestoreCursorSettingsDefaults: { [weak cursorSettingsStore] in
                cursorSettingsStore?.restoreDefaults() ?? CursorSettings()
            },
            onCursorMovementBindingChange: {
                [weak cursorMovementBindingStore, weak shortcutCoordinator] direction, shortcut in
                guard let cursorMovementBindingStore else {
                    return .failure(.unavailable)
                }

                let result = cursorMovementBindingStore.update(
                    direction, to: shortcut, shortcuts: shortcutCoordinator?.currentShortcuts ?? [:]
                )
                if case .success(let bindings) = result {
                    shortcutCoordinator?.updateCursorMovementBindings(bindings)
                }
                return result
            },
            onRestoreCursorMovementBindingsDefaults: {
                [weak cursorMovementBindingStore, weak shortcutCoordinator] in
                let bindings = cursorMovementBindingStore?.restoreDefaults()
                    ?? CursorMovementBindings()
                shortcutCoordinator?.updateCursorMovementBindings(bindings)
                return bindings
            },
            onRecordingStateChanged: { [weak shortcutCoordinator] isRecording in
                if isRecording {
                    shortcutCoordinator?.suspendRegistrations()
                } else {
                    _ = shortcutCoordinator?.resumeRegistrations()
                }
            }
        )
        self.settingsWindowController = settingsWindowController

        let registrationResult = shortcutCoordinator.start(
            handlers: [
                .activateCursorMode: { [weak self] type, _ in
                    guard type == .keyDown else { return }
                    if self?.shortcutCoordinator?.modeOptions.separateExitEnabled == true {
                        self?.cursorControlService?.start()
                    } else {
                        self?.cursorControlService?.toggle()
                    }
                },
                .exitCursorMode: { [weak self] type, _ in
                    guard type == .keyDown else { return }
                    self?.cursorControlService?.stop()
                },
                .scrollLeft: { [weak self] type, repeatCount in
                    guard type == .keyDown else { return }
                    self?.scroll(.left, repeatCount: repeatCount)
                },
                .scrollDown: { [weak self] type, repeatCount in
                    guard type == .keyDown else { return }
                    self?.scroll(.down, repeatCount: repeatCount)
                },
                .scrollUp: { [weak self] type, repeatCount in
                    guard type == .keyDown else { return }
                    self?.scroll(.up, repeatCount: repeatCount)
                },
                .scrollRight: { [weak self] type, repeatCount in
                    guard type == .keyDown else { return }
                    self?.scroll(.right, repeatCount: repeatCount)
                },
                .autoClicker: { [weak self] type, _ in
                    if type == .keyDown {
                        self?.autoClickerService?.start()
                    } else if type == .keyUp {
                        self?.autoClickerService?.stop()
                    }
                },
                .middleClick: { [weak self] type, repeatCount in
                    guard type == .keyDown, repeatCount == 0 else { return }
                    if let location = CGEvent(source: nil)?.location {
                        _ = self?.mouseClickService?.click(.middle, at: location)
                    }
                },
                .mouseJiggler: { [weak self] type, repeatCount in
                    guard type == .keyDown, repeatCount == 0 else { return }
                    self?.jigglerService?.toggle()
                }
            ],
            cursorMovementBindings: cursorMovementBindingStore.load(),
            onCursorInput: { [weak cursorControlService] input in
                cursorControlService?.handle(input)
            },
            onInputTapDisabled: { [weak cursorControlService] in
                cursorControlService?.releaseAllMovementKeys()
            }
        )
        if case .registrationFailure(let message) = registrationResult {
            logger.error("\(message)")
        }

        maybeShowOnboarding()
        settingsWindowController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scrollService?.refreshAccessibilityPermission()
        cursorControlService?.refreshAccessibilityPermission()
    }

    func applicationDidResignActive(_ notification: Notification) {
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutCoordinator?.unregisterAll()
    }

    private func scroll(_ direction: ScrollDirection, repeatCount: Int) {
        scrollService?.scroll(
            direction,
            isInteractionActive: false,
            repeatCount: repeatCount
        )
    }

    private func maybeShowOnboarding() {
        let key = "CursorControl.HasShownCursorScrollOnboarding.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        UserDefaults.standard.set(true, forKey: key)
        onboardingWindowController?.show()
    }
}
