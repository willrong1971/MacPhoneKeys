import Foundation

@main enum AppPreferencesTests {
    static func main() {
        let suiteName = "MacPhoneKeys.AppPreferencesTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create an isolated preferences suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else { fatalError(message) }
        }
        func reopenedPreferences() -> AppPreferences {
            guard let reopened = UserDefaults(suiteName: suiteName) else {
                fatalError("Could not reopen the isolated preferences suite")
            }
            return AppPreferences(defaults: reopened)
        }

        // Always inject the isolated suite; this test never accesses .standard.
        let preferences = AppPreferences(defaults: defaults)
        expect(preferences.showsInputHint, "A missing preference shows the hint by default")
        expect(defaults.persistentDomain(forName: suiteName)?["showsInputHint"] == nil,
               "Reading the default must not persist a preference")

        preferences.showsInputHint = false
        expect(!preferences.showsInputHint, "The hint can be disabled")
        expect(defaults.persistentDomain(forName: suiteName)?["showsInputHint"] as? Bool == false,
               "Disabling writes false to the documented preference key")
        expect(!reopenedPreferences().showsInputHint,
               "A new preferences instance using the same suite retains false")

        let secondInstance = reopenedPreferences()
        secondInstance.showsInputHint = true
        expect(secondInstance.showsInputHint, "The hint can be enabled again")
        expect(preferences.showsInputHint, "Existing instances observe the shared updated preference")
        expect(defaults.persistentDomain(forName: suiteName)?["showsInputHint"] as? Bool == true,
               "Re-enabling persists true")
        expect(reopenedPreferences().showsInputHint,
               "A reopened preferences instance retains true")

        defaults.removeObject(forKey: "showsInputHint")
        expect(preferences.showsInputHint && reopenedPreferences().showsInputHint,
               "Removing the stored preference restores the default across instances")
        print("PASS: \(checks) isolated app preference checks")
    }
}
