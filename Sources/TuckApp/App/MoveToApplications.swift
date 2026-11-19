import AppKit

/// Offers once, at launch, to move Tuck into Applications when it is running from somewhere it can't
/// stay: its disk image, or the temporary copy macOS runs when a downloaded app is opened where it
/// landed (App Translocation), whose path changes every launch. Neither can open at login. Declined, it
/// never asks again.
enum MoveToApplications {
    private static let declinedKey = "MoveToApplicationsDeclined"

    private enum Origin {
        case diskImage, translocated
    }

    /// What is already in Applications under Tuck's name.
    private enum Destination {
        /// Nothing, so the copy goes straight in.
        case free(URL)
        /// Another copy of Tuck, with the same bundle ID, which the move replaces through the Trash.
        case tuck(URL, Bundle)
        /// Some other app of the same name, which is never replaced.
        case taken
    }

    /// True when Tuck is about to quit and reopen from Applications, so launch should go no further.
    static func offerIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", let origin = origin(of: bundle),
              !UserDefaults.standard.bool(forKey: declinedKey) else { return false }
        let destination = destination(named: bundle.lastPathComponent)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move Tuck to Applications?"
        alert.informativeText = switch origin {
        case .diskImage:
            "Tuck is running from its disk image. In Applications it can open at login, and it keeps working once "
                + "the disk image is ejected."
        case .translocated:
            "macOS is running Tuck from a temporary copy. In Applications it can open at login, and it stays where "
                + "you put it."
        }
        if case .tuck(_, let installed) = destination {
            alert.informativeText += "\n\n" + replacementNote(for: installed)
        }
        if case .tuck = destination {
            alert.addButton(withTitle: "Replace")
        } else {
            alert.addButton(withTitle: "Move to Applications")
        }
        alert.addButton(withTitle: "Don't Move")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return false
        }
        guard let moved = copyToApplications(bundle, to: destination) else {
            if case .taken = destination {
                explain("Tuck couldn't move itself",
                        "Applications already has a different app called Tuck. Rename that one, then drag Tuck into "
                            + "Applications. Until then it carries on from here.")
            } else {
                explain("Tuck couldn't move itself",
                        "Drag Tuck into your Applications folder, then open it from there. Until then it carries on from here.")
            }
            return false
        }
        guard relaunch(from: moved) else {
            explain("Tuck is in Applications now", "Quit this copy, then open Tuck from Applications.")
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    private static func explain(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private static func origin(of bundle: URL) -> Origin? {
        if bundle.path.contains("/AppTranslocation/") { return .translocated }
        let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return bundle.path.hasPrefix("/Volumes/") && readOnly ? .diskImage : nil
    }

    /// Only a copy with this copy's bundle ID counts as Tuck; with no ID on either side nothing does.
    private static func destination(named name: String) -> Destination {
        let files = FileManager.default
        let applications = files.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        let url = applications.appendingPathComponent(name)
        guard files.fileExists(atPath: url.path) else { return .free(url) }
        guard let ours = Bundle.main.bundleIdentifier, let installed = Bundle(url: url),
              installed.bundleIdentifier == ours else { return .taken }
        return .tuck(url, installed)
    }

    /// Names both versions, with their builds when the versions match, so the person knows which way the
    /// replacement goes, and says so when the copy being replaced is the newer one.
    private static func replacementNote(for installed: Bundle) -> String {
        let info = installed.infoDictionary
        guard let mine = ReleaseInfo.version, let theirs = info?["CFBundleShortVersionString"] as? String else {
            return "Applications already has a copy of Tuck. Moving puts this one in its place, and that one in the Trash."
        }
        let theirBuild = info?["CFBundleVersion"] as? String
        let newer = switch theirs.compare(mine.short, options: .numeric) {
        case .orderedDescending: true
        case .orderedAscending: false
        case .orderedSame: (theirBuild ?? "").compare(mine.build ?? "", options: .numeric) == .orderedDescending
        }
        var installedVersion = theirs, thisVersion = mine.short
        if theirs == mine.short, theirBuild != mine.build {
            installedVersion += theirBuild.map { " (build \($0))" } ?? ""
            thisVersion += mine.build.map { " (build \($0))" } ?? ""
        }
        if installedVersion == thisVersion {
            return "Applications already has Tuck \(installedVersion), the same version as this one. Moving puts this "
                + "copy in its place, and that one in the Trash."
        }
        return "Applications already has Tuck \(installedVersion)" + (newer ? ", which is newer than this one" : "")
            + ". Moving puts this copy, Tuck \(thisVersion), in its place, and that one in the Trash."
    }

    /// Copies the bundle into /Applications, replacing another copy of Tuck there (moved to the Trash, so
    /// it can be got back) but never another app of the same name. The copy is made beside it first,
    /// under a hidden name without ".app" so Launch Services never takes it for an app, and only once it
    /// is complete does the old copy go to the Trash. So a copy that fails part-way, from a full disk or a
    /// disk image ejected mid-copy, leaves Applications as it was. The copy loses the download's
    /// quarantine flag, which this launch has already been through, so macOS doesn't translocate it again.
    private static func copyToApplications(_ bundle: URL, to destination: Destination) -> URL? {
        let target: URL, replacing: Bool
        switch destination {
        case .free(let url): (target, replacing) = (url, false)
        case .tuck(let url, _): (target, replacing) = (url, true)
        case .taken: return nil
        }
        let files = FileManager.default
        let staged = target.deletingLastPathComponent().appendingPathComponent(".Tuck-moving-\(UUID().uuidString)")
        guard (try? files.copyItem(at: bundle, to: staged)) != nil else {
            try? files.removeItem(at: staged)
            return nil
        }
        removeQuarantine(under: staged)
        var trashed: NSURL?
        if replacing, (try? files.trashItem(at: target, resultingItemURL: &trashed)) == nil {
            try? files.removeItem(at: staged)
            return nil
        }
        guard (try? files.moveItem(at: staged, to: target)) != nil else {
            // Both are renames on one disk, so this is unlikely; the old copy goes back where it was.
            if let trashed = trashed as URL? { try? files.moveItem(at: trashed, to: target) }
            try? files.removeItem(at: staged)
            return nil
        }
        return target
    }

    private static func removeQuarantine(under root: URL) {
        removexattr(root.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = items?.nextObject() as? URL {
            removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// Opens the moved copy once this one has quit, so two Tucks never share the notch.
    private static func relaunch(from app: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                             "sh", String(getpid()), app.path]
        return (try? process.run()) != nil
    }
}
