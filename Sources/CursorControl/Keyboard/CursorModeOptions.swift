import Foundation

struct CursorModeOptions: Equatable {
    var separateExitEnabled = false
}

final class CursorModeOptionsStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> CursorModeOptions {
        CursorModeOptions(
            separateExitEnabled: defaults.bool(forKey: "CursorControl.SeparateExitEnabled")
        )
    }
    func save(_ options: CursorModeOptions) {
        defaults.set(options.separateExitEnabled, forKey: "CursorControl.SeparateExitEnabled")
    }
}
