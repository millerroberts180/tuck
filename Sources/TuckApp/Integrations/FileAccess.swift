import AppKit

/// What macOS lets Tuck read of the files people drop. Outside the App Store sandbox, macOS guards a
/// few places and asks the first time an app touches each one: the Desktop, Documents and Downloads
/// folders, iCloud Drive, and external and network drives. Tuck touches a dropped file to show its
/// thumbnail, kind and size and to follow it if it moves, so without these, a drop from a new place
/// stops for a prompt.
///
/// Setup covers them up front. Full Disk Access covers every place at once and never prompts; no app can
/// ask for it, so it is switched on in System Settings. The folders can instead be asked for now, one
/// prompt each. External and network drives can only be asked about once one is connected, so Full Disk
/// Access is the only way to cover them in advance.
enum FileAccess {
    enum Folder: String, CaseIterable, Identifiable, Sendable {
        case desktop, documents, downloads, iCloudDrive

        var id: Self { self }

        var title: String {
            switch self {
            case .desktop: "Desktop"
            case .documents: "Documents"
            case .downloads: "Downloads"
            case .iCloudDrive: "iCloud Drive"
            }
        }

        /// Where the folder is, or nil when this Mac doesn't have it (iCloud Drive switched off).
        var url: URL? {
            let files = FileManager.default
            switch self {
            case .desktop: return files.urls(for: .desktopDirectory, in: .userDomainMask).first
            case .documents: return files.urls(for: .documentDirectory, in: .userDomainMask).first
            case .downloads: return files.urls(for: .downloadsDirectory, in: .userDomainMask).first
            case .iCloudDrive:
                let drive = files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                return files.fileExists(atPath: drive.path) ? drive : nil
            }
        }

        /// The folders this Mac has, in the order they are asked for.
        static var present: [Folder] { allCases.filter { $0.url != nil } }
    }

    /// Whether Tuck has Full Disk Access: whether it can open a file that only Full Disk Access opens (the
    /// user's own privacy database, opened for reading and closed at once). Checking never prompts.
    static var hasFullDiskAccess: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        let descriptor = open(probe, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks for each folder in turn by looking at what it holds, which shows macOS's prompt for any folder
    /// not yet decided (one already decided answers at once, with no prompt). Runs off the main thread,
    /// since each prompt waits for its answer, and reports each answer on the main thread.
    static func request(_ folders: [Folder], answered: @escaping (Folder, Bool) -> Void,
                        finished: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            for folder in folders {
                guard let url = folder.url else { continue }
                let allowed = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
                DispatchQueue.main.async { answered(folder, allowed) }
            }
            DispatchQueue.main.async(execute: finished)
        }
    }
}
