import Foundation
import Security

/// Tuck once had a trial and licence keys. Builds from then kept the days the trial had counted in
/// UserDefaults and in the login Keychain, and a licence key in UserDefaults. Each launch deletes those
/// three entries and nothing else; once they are gone there is nothing to do. A Keychain item made by
/// a different build is refused the delete without the person being asked (`errSecInvalidOwnerEdit`),
/// so it stays and is tried again at the next launch. Uninstall's removing the settings removes the
/// first two as well.
enum TrialLeftovers {
    static func remove(defaults: UserDefaults = .standard) {
        for key in ["TrialRecord", "LicenseKey"] where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
        // The item as builds with a trial filed it: a generic password under the bundle ID.
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: ReleaseInfo.bundleID,
                                   kSecAttrAccount as String: "trial"]
        SecItemDelete(item as CFDictionary)
    }
}
