import AppKit
import Quartz
import TuckCore

/// What a drop carries, in order of preference.
enum DropPayload {
    /// File references, links, music links and text, read straight off the pasteboard.
    case items([HeldItem])
    /// Files that only exist once the source writes them (Mail messages, Photos, images from some apps).
    case promises([NSFilePromiseReceiver])
    /// Raw image data with no file behind it.
    case image(Data)
}

/// Reads explicit drops. Files stay references to the original location; promised files and raw images
/// are written into Tuck's received-files folder because there is no original to point at.
enum DropReader {
    static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
    static let directTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]
    static let acceptedTypes: [NSPasteboard.PasteboardType] = directTypes + promiseTypes + imageTypes

    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: acceptedTypes) != nil
    }

    /// Checks a pasteboard's type list only; used once per drag to decide whether to invite a drop.
    static func isDroppable(types: [NSPasteboard.PasteboardType]?) -> Bool {
        guard let types else { return false }
        return !Set(types).isDisjoint(with: acceptedTypes)
    }

    /// What a drag carries, for the drop target's words, from its type list alone.
    static func kind(types: [NSPasteboard.PasteboardType]?) -> DropKind {
        let types = Set(types ?? [])
        return DropKind.kind(hasFiles: types.contains(.fileURL), hasLink: types.contains(.URL),
                             arrivesAsFile: !types.isDisjoint(with: promiseTypes + imageTypes))
    }

    static func kind(of pasteboard: NSPasteboard) -> DropKind { kind(types: pasteboard.types) }

    static func payload(from pasteboard: NSPasteboard, sourceAppName: String? = nil) -> DropPayload? {
        let hasFiles = pasteboard.availableType(from: [.fileURL]) != nil
        // A promise is preferred over the source's URL unless that URL is a real web link: a Mail message
        // should arrive as the message file, a link from a browser as the link.
        if !hasFiles, !hasWebURL(pasteboard),
           let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            return .promises(receivers)
        }
        let items = directItems(from: pasteboard, sourceAppName: sourceAppName)
        if !items.isEmpty { return .items(items) }
        if let type = pasteboard.availableType(from: imageTypes), let data = pasteboard.data(forType: type) {
            return .image(data)
        }
        return nil
    }

    /// Per pasteboard item: a file reference, else a URL, else plain text.
    static func directItems(from pasteboard: NSPasteboard, sourceAppName: String?) -> [HeldItem] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            if let raw = item.string(forType: .fileURL), let url = URL(string: raw), url.isFileURL {
                return .file(url.standardizedFileURL, sourceAppName: sourceAppName)
            }
            if let raw = item.string(forType: .URL), let url = URL(string: raw) {
                return HeldItemClassifier.item(for: url, sourceAppName: sourceAppName)
            }
            if let text = item.string(forType: .string) {
                return HeldItemClassifier.item(forText: text, sourceAppName: sourceAppName)
            }
            return nil
        }
    }

    private static func hasWebURL(_ pasteboard: NSPasteboard) -> Bool {
        (pasteboard.pasteboardItems ?? []).contains { item in
            guard let raw = item.string(forType: .URL), let scheme = URL(string: raw)?.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }
}

/// Receives promised files and raw images into a fresh folder of the received-files store.
enum ReceivedIntake {
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    static func receive(_ receivers: [NSFilePromiseReceiver], into store: ReceivedFileStore,
                        completion: @escaping ([URL]) -> Void) {
        guard let slot = try? store.makeSlot() else { return completion([]) }
        let group = DispatchGroup()
        let lock = NSLock()
        var received: [URL] = []
        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(atDestination: slot, options: [:], operationQueue: queue) { url, error in
                if error == nil {
                    lock.lock()
                    received.append(url.standardizedFileURL)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if received.isEmpty { store.discard(slot) }
            completion(received.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
    }

    /// Writes dropped image data as a PNG named after the time it arrived.
    static func receive(image data: Data, into store: ReceivedFileStore, now: Date = Date()) -> URL? {
        guard let slot = try? store.makeSlot() else { return nil }
        let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) ?? data
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = slot.appendingPathComponent("Image \(formatter.string(from: now)).png")
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            store.discard(url)
            return nil
        }
    }
}

/// Zips held files with the system's `ditto`, the same tool the Finder's Compress uses, so archives keep
/// metadata and open anywhere. Runs on a background queue and only while zipping.
enum ZipArchiver {
    enum Failure: Error { case noDestination, toolFailed }

    static func zip(_ sources: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        guard let destination = ArchiveNaming.archiveURL(
            for: sources,
            fallbackDirectory: downloads,
            isWritable: { fileManager.isWritableFile(atPath: $0.path) },
            exists: { fileManager.fileExists(atPath: $0.path) }
        ) else { return completion(.failure(Failure.noDestination)) }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try archive(sources, to: destination) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func archive(_ sources: [URL], to destination: URL) throws -> URL {
        let fileManager = FileManager.default
        var staging: URL?
        defer { if let staging { try? fileManager.removeItem(at: staging.deletingLastPathComponent()) } }

        let source: URL
        var arguments = ["-c", "-k", "--sequesterRsrc"]
        if sources.count == 1 {
            source = sources[0]
            // A folder keeps its own name as the archive's root; a single file sits at the root itself.
            if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                arguments.append("--keepParent")
            }
        } else {
            // ditto archives one folder, so several files are gathered into a temporary folder first.
            // Copies on APFS are clones: no extra disk space and near-instant.
            let folder = fileManager.temporaryDirectory
                .appendingPathComponent("TuckZip-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(destination.deletingPathExtension().lastPathComponent, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            staging = folder
            var used = Set<String>()
            for url in sources {
                var name = url.lastPathComponent
                var counter = 2
                while used.contains(name.lowercased()) {
                    name = "\(url.deletingPathExtension().lastPathComponent) \(counter)" + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")
                    counter += 1
                }
                used.insert(name.lowercased())
                try fileManager.copyItem(at: url, to: folder.appendingPathComponent(name))
            }
            source = folder
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments + [source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.toolFailed }
        return destination
    }
}

/// Opens held items with their default apps. A stack is revealed in the Finder.
struct WorkspaceItemOpener: HeldItemOpening {
    func open(_ item: HeldItem) -> OpenOutcome {
        let workspace = NSWorkspace.shared
        switch item.kind {
        case .stack:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return .failed(reason: "Files missing") }
            workspace.activateFileViewerSelecting(urls)
            return .opened(appName: "Finder")
        case .file:
            guard let url = item.url, FileManager.default.fileExists(atPath: url.path) else {
                return .failed(reason: "File missing")
            }
            let appName = workspace.urlForApplication(toOpen: url).map(Self.name(ofApp:)) ?? "its app"
            return workspace.open(url) ? .opened(appName: appName) : .failed(reason: "Couldn't open")
        case .link, .music:
            guard let url = item.url else { return .failed(reason: "Missing link") }
            let appName = workspace.urlForApplication(toOpen: url).map(Self.name(ofApp:)) ?? "your browser"
            return workspace.open(url) ? .opened(appName: appName) : .failed(reason: "Couldn't open")
        case .text:
            return .failed(reason: "Text is copied, not opened")
        }
    }

    private static func name(ofApp url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Quick Look for held files, through the system's shared preview panel: the same preview the Finder
/// shows on Space, with its own arrows between a stack's files. Tuck comes forward while it shows, so
/// the panel takes Space and Escape.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPresenter()
    private var urls: [URL] = []

    func show(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = existing
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
