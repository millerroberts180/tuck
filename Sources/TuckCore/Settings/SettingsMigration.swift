import Foundation

/// Tuck keeps its settings in macOS's preferences under its bundle ID, which was `app.tuck.prototype`
/// until it became `com.millerroberts.Tuck`. At the first launch under the new ID, everything saved
/// under the old one is copied across, so nobody starts again from the defaults. The old domain is
/// never deleted, so a build that still has the old ID keeps its own. Accessibility and Open at Login
/// don't come across: macOS keys them to the app's identity, not to its preferences.
public enum SettingsMigration {
    /// The bundle ID Tuck had before it had its own.
    public static let previousBundleID = "app.tuck.prototype"

    /// Copies every key saved under `previous` into `bundleID`'s domain, but only while `bundleID`'s
    /// domain has nothing saved yet and `previous` has something. Without a bundle ID (`swift run`), or
    /// still under the previous one, it does nothing. Returns whether anything was copied.
    @discardableResult
    public static func carryOver(to bundleID: String?, from previous: String = previousBundleID,
                                 in defaults: UserDefaults = .standard) -> Bool {
        guard let bundleID, bundleID != previous else { return false }
        if let saved = defaults.persistentDomain(forName: bundleID), !saved.isEmpty { return false }
        guard let old = defaults.persistentDomain(forName: previous), !old.isEmpty else { return false }
        // The new domain is empty, so setting it whole is copying the old keys into it.
        defaults.setPersistentDomain(old, forName: bundleID)
        return true
    }
}
