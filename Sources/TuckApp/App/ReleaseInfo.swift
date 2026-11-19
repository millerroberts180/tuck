import Foundation

/// Where Tuck points people, and what it says about itself: read from the bundle's Info.plist, which
/// scripts/build-app.sh stamps from Support/release.env. A value left unset there keeps the source plist's
/// placeholder on tuck.example, so a test build still has somewhere to point. Tuck never opens any of
/// these on its own, only when someone clicks one.
enum ReleaseInfo {
    static var websiteURL: URL { url("TuckWebsiteURL", placeholder: "https://tuck.example") }
    static var privacyPolicyURL: URL { url("TuckPrivacyPolicyURL", placeholder: "https://tuck.example/privacy") }
    static var eulaURL: URL { url("TuckEULAURL", placeholder: "https://tuck.example/eula") }
    /// A help page, if there is one; support is otherwise by email.
    static var supportURL: URL? { string("TuckSupportURL").flatMap(URL.init(string:)) }
    static var supportEmail: String { string("TuckSupportEmail") ?? "support@tuck.example" }
    static var supportMailURL: URL { URL(string: "mailto:\(supportEmail)") ?? websiteURL }

    static var copyright: String { string("NSHumanReadableCopyright") ?? "" }

    /// "1.0.0" and "20261106.74534.53" (the UTC date, the time and the commit count, as scripts/release.sh
    /// makes it), or nil for a bare `swift run`, which has no bundle of its own.
    static var version: (short: String, build: String?)? {
        guard let short = string("CFBundleShortVersionString") else { return nil }
        return (short, string("CFBundleVersion"))
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "app.tuck" }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func url(_ key: String, placeholder: String) -> URL {
        string(key).flatMap(URL.init(string:)) ?? URL(string: placeholder)!
    }
}
