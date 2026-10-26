import Foundation

struct AppPreferences {
    private let defaults: UserDefaults
    private static let inputHintKey = "showsInputHint"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showsInputHint: Bool {
        get { defaults.object(forKey: Self.inputHintKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.inputHintKey) }
    }
}
