import Foundation
import Testing
@testable import TuckCore

@Suite("Settings carried over from the old bundle ID")
struct SettingsMigrationTests {
    /// A pair of throwaway preferences domains, one pair per test so tests running side by side never
    /// share one. They are removed before the test and at its end, so no real settings are touched and
    /// nothing is left behind.
    struct Domains {
        let old: String
        let new: String

        init(_ test: String) {
            old = "com.millerroberts.Tuck.tests.\(test).old"
            new = "com.millerroberts.Tuck.tests.\(test).new"
            remove()
        }

        func remove() {
            for domain in [old, new] {
                UserDefaults.standard.removePersistentDomain(forName: domain)
                // cfprefsd keeps an emptied domain's file, so that goes too.
                let file = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/\(domain).plist")
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    let defaults = UserDefaults.standard

    @Test func copiesEveryKeyWhenTheNewDomainIsEmpty() {
        let domains = Domains("copies")
        defer { domains.remove() }
        defaults.setPersistentDomain(["hapticsEnabled": false, "cardLayout": "large", "setupCompleted": true],
                                     forName: domains.old)

        #expect(SettingsMigration.carryOver(to: domains.new, from: domains.old, in: defaults))

        let copied = defaults.persistentDomain(forName: domains.new)
        #expect(copied?.count == 3)
        #expect(copied?["hapticsEnabled"] as? Bool == false)
        #expect(copied?["cardLayout"] as? String == "large")
        #expect(UserDefaults(suiteName: domains.new)?.bool(forKey: "setupCompleted") == true)
        // The old domain stays as it was.
        #expect(defaults.persistentDomain(forName: domains.old)?.count == 3)
    }

    @Test func leavesANewDomainThatAlreadyHasKeys() {
        let domains = Domains("keeps-new")
        defer { domains.remove() }
        defaults.setPersistentDomain(["cardLayout": "large", "hapticsEnabled": false], forName: domains.old)
        defaults.setPersistentDomain(["cardLayout": "small"], forName: domains.new)

        #expect(!SettingsMigration.carryOver(to: domains.new, from: domains.old, in: defaults))

        let kept = defaults.persistentDomain(forName: domains.new)
        #expect(kept?.count == 1)
        #expect(kept?["cardLayout"] as? String == "small")
    }

    @Test func doesNothingWhenTheOldDomainIsMissing() {
        let domains = Domains("no-old")
        defer { domains.remove() }

        #expect(!SettingsMigration.carryOver(to: domains.new, from: domains.old, in: defaults))

        #expect(defaults.persistentDomain(forName: domains.new)?.isEmpty ?? true)
    }

    @Test func doesNothingWithoutABundleIDOrUnderTheOldOne() {
        let domains = Domains("no-bundle-id")
        defer { domains.remove() }
        defaults.setPersistentDomain(["cardLayout": "large"], forName: domains.old)

        #expect(!SettingsMigration.carryOver(to: nil, from: domains.old, in: defaults))
        #expect(!SettingsMigration.carryOver(to: domains.old, from: domains.old, in: defaults))

        #expect(defaults.persistentDomain(forName: domains.old)?.count == 1)
    }
}
