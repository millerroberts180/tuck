import AppKit
import TuckCore

/// Uninstall Tuck…, from Settings › About. The app delegate first gives everything back (every rested
/// app woken, every tucked window brought back) and stops if anything won't come back, before anything
/// is deleted. Then this turns off Open at Login, deletes Tuck's files and settings, resets its
/// permissions and moves the app to the Trash. Whatever it can't do itself is listed for the person to
/// finish.
enum Uninstaller {
    /// Says why nothing was deleted, and offers the way to fix it when the cause is the permission.
    static func explainStop(kept: Int, resting: [String]) {
        // Windows come first, so the sentence starts with a capital either way.
        var problems: [String] = []
        if kept > 0 {
            problems.append(kept == 1 ? "A tucked window couldn't come back" : "\(kept) tucked windows couldn't come back")
        }
        if !resting.isEmpty { problems.append("\(ListFormatter.localizedString(byJoining: resting)) couldn't be woken") }
        let trusted = AX.isTrusted
        let alert = NSAlert()
        alert.messageText = "Nothing was deleted"
        alert.informativeText = problems.joined(separator: " and ") + ", so Tuck stopped before removing anything. "
            + (trusted ? "Try again, or close those first." : "Allow Tuck in \(AX.paneName), then try again.")
        alert.addButton(withTitle: "OK")
        if !trusted { alert.addButton(withTitle: "Open System Settings…") }
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { AX.openAccessibilitySettings() }
    }

    /// Everything after the hand-back, in order. Returns what is left to do by hand, one step per line.
    static func removeEverything(supportFolder: URL) -> [String] {
        var leftovers: [String] = []
        LoginItem.set(false)
        if LoginItem.isEnabled { leftovers.append("Remove Tuck from Login Items in System Settings › General.") }

        // Only what Tuck wrote is deleted, never the folder wholesale: a debug build can be pointed at any
        // folder, and one Tuck didn't make keeps everything that isn't Tuck's.
        if !SupportFolder(directory: supportFolder).removeTucksFiles() {
            let path = (supportFolder.path as NSString).abbreviatingWithTildeInPath
            leftovers.append("Look in \(path), where Tuck left what it didn't make, and delete the folder if you "
                             + "don't need it.")
        }
        // A bare `swift run` build has no bundle ID: its settings sit under its name, and it has no
        // permissions of its own to reset.
        let bundleID = Bundle.main.bundleIdentifier
        UserDefaults.standard.removePersistentDomain(forName: bundleID ?? ProcessInfo.processInfo.processName)
        if let bundleID, !resetPermissions(of: bundleID) {
            leftovers.append("In System Settings › Privacy & Security, remove Tuck from \(AX.paneName), and from "
                             + "Full Disk Access and Files & Folders if it's there.")
        }

        if let step = moveAppToTrash() { leftovers.append(step) }
        return leftovers
    }

    /// The last word before Tuck quits.
    static func showFinished(leftovers: [String]) {
        let alert = NSAlert()
        if leftovers.isEmpty {
            alert.messageText = "Tuck is uninstalled"
            alert.informativeText = "Your windows are back where they were, and Tuck's settings, files and permissions "
                + "are gone."
        } else {
            alert.messageText = "Tuck is almost uninstalled"
            alert.informativeText = "Your windows are back where they were. A few things are left to do by hand:\n\n"
                + leftovers.map { "• " + $0 }.joined(separator: "\n")
        }
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
    }

    /// `tccutil` finds the app through Launch Services, so it works for a copy macOS knows about, as any
    /// app in Applications is. It exits with an error for one it can't find.
    private static func resetPermissions(of bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "All", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The running app goes to the Trash, where it can still be got back; it keeps running until it quits.
    /// A copy on a disk image, or one macOS is running from a temporary place, can't be moved.
    private static func moveAppToTrash() -> String? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return nil }
        if app.path.contains("/AppTranslocation/") { return "Drag Tuck to the Trash from where you keep it." }
        if (try? app.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return "Eject Tuck's disk image."
        }
        guard (try? FileManager.default.trashItem(at: app, resultingItemURL: nil)) == nil else { return nil }
        let folder = (app.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        return "Drag Tuck to the Trash from \(folder)."
    }
}
