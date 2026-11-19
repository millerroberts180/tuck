import Foundation

/// Works out what a copy is from its text and where it came from, once, when it is recorded. The first
/// match wins, and dates are checked before phone numbers so "2026-11-08" is a date. Nothing here touches
/// the network or the disk.
public enum ContentClassifier {
    /// Apps whose copies are code even when the text alone wouldn't say so.
    static let codeSourceBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "dev.zed.Zed", "com.apple.dt.Xcode",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.barebones.bbedit", "com.panic.Nova"
    ]

    static let screenshotBundleIDs: Set<String> = ["com.apple.screencaptureui", "com.apple.screenshot.launcher"]

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "alac", "ogg", "oga",
                                               "wma", "m4b", "caf", "opus"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "wmv", "flv",
                                               "3gp", "m2ts", "mts", "ts", "ogv"]

    /// Prefixes that mark a key or token, and what to call it.
    static let secretPrefixes: [(prefix: String, name: String)] = [
        ("sk-ant-", "Anthropic API key"), ("sk-proj-", "OpenAI API key"), ("sk-", "API key"),
        ("github_pat_", "GitHub token"), ("ghp_", "GitHub token"), ("gho_", "GitHub token"), ("ghu_", "GitHub token"),
        ("ghs_", "GitHub token"), ("xoxb-", "Slack token"), ("xoxp-", "Slack token"), ("xapp-", "Slack token"),
        ("AKIA", "AWS access key"), ("ASIA", "AWS access key"), ("AIza", "Google API key"),
        ("ya29.", "Google OAuth token"), ("glpat-", "GitLab token"), ("npm_", "npm token"), ("pypi-", "PyPI token"),
        ("shpat_", "Shopify token"), ("rk_live_", "Stripe key"), ("sk_live_", "Stripe key"), ("pk_live_", "Stripe key")
    ]

    static let shellPrefixes = ["git", "npm", "npx", "brew", "sudo", "cd", "ls", "curl", "ssh", "docker", "kubectl",
                                "python", "python3", "pip", "pip3", "swift", "xcodebuild", "make", "cargo", "go", "yarn",
                                "pnpm", "open", "cat", "echo", "export", "defaults", "rm", "mkdir", "cp", "mv"].map { $0 + " " }

    static let codeMarkers = ["{", "}", ";", "=>", "==", "func ", "def ", "function ", "class ", "import ", "const ",
                              "let ", "var ", "public ", "private ", "#include", "</", "/>", "return ", "println",
                              "console.log", "::"]

    private static let emailPattern = try! NSRegularExpression(
        pattern: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$", options: [.caseInsensitive])
    private static let hexColorPattern = try! NSRegularExpression(
        pattern: "^#?([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$", options: [.caseInsensitive])
    private static let rgbColorPattern = try! NSRegularExpression(
        pattern: "^rgba?\\(\\s*([0-9.]+%?)[\\s,]+([0-9.]+%?)[\\s,]+([0-9.]+%?)(?:[\\s,/]+([0-9.]+%?))?\\s*\\)$",
        options: [.caseInsensitive])
    private static let timePattern = try! NSRegularExpression(
        pattern: "\\b\\d{1,2}[:.]\\d{2}\\b|\\b\\d{1,2}\\s*(am|pm|a\\.m\\.|p\\.m\\.)|\\bnoon\\b|\\bmidnight\\b|\\bo'clock\\b",
        options: [.caseInsensitive])
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)

    /// What a copied string is. `hasRichText` says the copy also carried styling worth keeping.
    public static func recognize(text: String, sourceBundleID: String? = nil, hasRichText: Bool = false) -> ContentRecognition {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        let isOneToken = !trimmed.contains(where: \.isWhitespace)

        if trimmed.uppercased().hasPrefix("BEGIN:VCARD") { return contact(trimmed) }
        if let color = color(in: trimmed) { return ContentRecognition(category: .color, color: color) }
        if let secret = secretName(trimmed) { return ContentRecognition(category: .secret, name: secret) }
        if isOneToken, let link = link(trimmed) { return link }
        if isEmail(trimmed) { return ContentRecognition(category: .email) }
        if isOneToken, isPath(trimmed) { return ContentRecognition(category: .path) }
        if isEmoji(trimmed) { return ContentRecognition(category: .emoji, name: emojiName(trimmed)) }
        if let detected = dateOrAddress(trimmed) { return detected }
        if isPhone(trimmed) { return ContentRecognition(category: .phone) }
        if isCode(trimmed) || codeSourceBundleIDs.contains(sourceBundleID ?? "") {
            return ContentRecognition(category: .code, language: language(of: trimmed))
        }
        return hasRichText ? ContentRecognition(category: .richText) : .text
    }

    /// What a file is, from its extension. `fromScreenshot` says the Screenshot app put it on the clipboard.
    public static func category(forFile url: URL, isDirectory: Bool, fromScreenshot: Bool = false) -> ContentCategory {
        if isDirectory, url.pathExtension.lowercased() != "app" { return .folder }
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            return fromScreenshot || url.lastPathComponent.hasPrefix("Screenshot ") ? .screenshot : .image
        }
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        return .file
    }

    /// Whether the copy came from the Screenshot app.
    public static func isScreenshotSource(_ bundleID: String?) -> Bool {
        screenshotBundleIDs.contains(bundleID ?? "")
    }

    // MARK: - Each kind

    public static func contact(_ card: String) -> ContentRecognition {
        let fields = VCard.fields(card)
        let name = fields.first { $0.key == "FN" }?.value
            ?? fields.first { $0.key == "N" }.map { VCard.nameFromN($0.value) }
        let org = fields.first { $0.key == "ORG" }?.value.replacingOccurrences(of: ";", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return ContentRecognition(category: .contact, name: name?.nonEmpty, detail: org?.nonEmpty)
    }

    public static func color(in text: String) -> RGBAColor? {
        guard text.count <= 40 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if text.hasPrefix("#"), let match = hexColorPattern.firstMatch(in: text, range: range),
           let hexRange = Range(match.range(at: 1), in: text) {
            return RGBAColor(hex: String(text[hexRange]))
        }
        if let match = rgbColorPattern.firstMatch(in: text, range: range) {
            func part(_ index: Int, scale: Double) -> Double? {
                guard let r = Range(match.range(at: index), in: text) else { return nil }
                let raw = String(text[r])
                if raw.hasSuffix("%") { return Double(raw.dropLast()).map { $0 / 100 } }
                return Double(raw).map { $0 / scale }
            }
            guard let red = part(1, scale: 255), let green = part(2, scale: 255), let blue = part(3, scale: 255),
                  [red, green, blue].allSatisfy({ (0...1).contains($0) }) else { return nil }
            let alpha = part(4, scale: 1) ?? 1
            return RGBAColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
        }
        return nil
    }

    static func secretName(_ text: String) -> String? {
        if text.hasPrefix("-----BEGIN"), text.contains("PRIVATE KEY") { return "Private key" }
        if text.hasPrefix("ssh-") || text.hasPrefix("ecdsa-sha2-") { return nil }
        guard !text.contains(where: \.isWhitespace) || text.hasPrefix("Bearer ") else { return nil }
        if text.hasPrefix("Bearer "), text.count >= 27, !text.dropFirst(7).contains(where: \.isWhitespace) {
            return "Bearer token"
        }
        guard text.count >= 20 else { return nil }
        if let match = secretPrefixes.first(where: { text.hasPrefix($0.prefix) }) { return match.name }
        if text.hasPrefix("eyJ"), text.filter({ $0 == "." }).count == 2 { return "JSON web token" }
        return nil
    }

    static func link(_ text: String) -> ContentRecognition? {
        let lower = text.lowercased()
        if lower.hasPrefix("mailto:") {
            return isEmail(String(text.dropFirst(7))) ? ContentRecognition(category: .email) : nil
        }
        let candidate = lower.hasPrefix("www.") ? "https://" + text : text
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else { return nil }
        if HeldItemClassifier.musicSchemes[scheme] != nil, url.host != nil || !url.path.isEmpty {
            return ContentRecognition(category: .music, name: HeldItemClassifier.musicProvider(for: url))
        }
        guard ["http", "https", "ftp"].contains(scheme), let host = url.host, host.contains(".") || host == "localhost"
        else { return nil }
        if let provider = HeldItemClassifier.musicProvider(for: url) {
            return ContentRecognition(category: .music, name: provider)
        }
        return ContentRecognition(category: .link)
    }

    static func isEmail(_ text: String) -> Bool {
        text.count <= 254 && emailPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func isPath(_ text: String) -> Bool {
        guard !text.contains("\n"), text.count <= 1024 else { return false }
        if text.hasPrefix("file://") { return URL(string: text)?.isFileURL == true }
        if text.hasPrefix("~/") { return text.count > 2 }
        guard text.hasPrefix("/"), !text.hasPrefix("//"), !text.hasPrefix("/*"), text.count > 1 else { return false }
        // A path has a name after its first slash; "/" alone, "/s" in a regex or "/24" in a subnet don't.
        let parts = text.split(separator: "/")
        return parts.count >= 1 && parts.allSatisfy { !$0.isEmpty } && text.rangeOfCharacter(from: .letters) != nil
    }

    static func isPhone(_ text: String) -> Bool {
        guard (7...25).contains(text.count) else { return false }
        let allowed = Set("+-() .0123456789")
        guard text.allSatisfy(allowed.contains) else { return false }
        let digits = text.filter(\.isNumber).count
        return (7...15).contains(digits)
    }

    static func isEmoji(_ text: String) -> Bool {
        guard text.count <= 16, !text.contains(where: \.isWhitespace) else { return false }
        return text.allSatisfy { character in
            let scalars = character.unicodeScalars
            guard let first = scalars.first else { return false }
            // A digit or # with the emoji variation selector is a keycap emoji; a bare one isn't.
            if first.properties.isEmojiPresentation { return true }
            return first.properties.isEmoji && scalars.count > 1 && first.value > 0x7F
        }
    }

    /// The emoji's Unicode name, in title case: "Grinning face", or the country for a flag.
    static func emojiName(_ text: String) -> String? {
        guard text.count == 1, let character = text.first else { return nil }
        let scalars = Array(character.unicodeScalars)
        let regional = scalars.compactMap { scalar -> Character? in
            guard (0x1F1E6...0x1F1FF).contains(scalar.value) else { return nil }
            return Character(Unicode.Scalar(scalar.value - 0x1F1E6 + 0x41)!)
        }
        if regional.count == 2, scalars.count == 2 {
            let code = String(regional)
            if let country = Locale(identifier: "en_GB").localizedString(forRegionCode: code) { return "Flag of " + country }
        }
        guard let name = scalars.first?.properties.name else { return nil }
        return name.lowercased().prefix(1).uppercased() + name.lowercased().dropFirst()
    }

    static func dateOrAddress(_ text: String) -> ContentRecognition? {
        guard text.count <= 500, let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range), match.range == range else { return nil }
        switch match.resultType {
        case .date:
            guard let date = match.date, text.rangeOfCharacter(from: .decimalDigits) != nil || text.count > 6 else { return nil }
            let hasTime = timePattern.firstMatch(in: text, range: range) != nil
            return ContentRecognition(category: .date, date: date, includesTime: hasTime)
        case .address:
            let lines = text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let components = match.addressComponents ?? [:]
            let street = components[.street] ?? lines.first
            let rest = [components[.city], components[.state], components[.country]].compactMap { $0 }
            let detail = rest.isEmpty ? lines.dropFirst().joined(separator: ", ") : rest.joined(separator: ", ")
            return ContentRecognition(category: .address, name: street?.nonEmpty, detail: detail.nonEmpty)
        default:
            return nil
        }
    }

    /// The code score: a point per marker, a point when most lines are indented, and a shell command
    /// on a short copy's first line. Two points pass for several lines, three for one.
    static func isCode(_ text: String) -> Bool {
        guard text.count >= 11 else { return false }
        if isJSON(text) { return true }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = lines.first.map(String.init) ?? ""
        if lines.count <= 3, shellPrefixes.contains(where: firstLine.hasPrefix) || firstLine.hasPrefix("./")
            || firstLine.hasPrefix("#!") || firstLine.hasPrefix("$ ") {
            return true
        }
        var score = codeMarkers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let isMultiLine = lines.count > 1
        if isMultiLine {
            let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let indented = filled.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
            if !filled.isEmpty, indented.count * 2 >= filled.count { score += 1 }
        }
        // Prose with a semicolon and a brace isn't code; prose rarely ends a line with one, though.
        if !isMultiLine, text.split(separator: " ").count > 8, !text.hasSuffix(";"), !text.hasSuffix("}") { score -= 1 }
        return score >= (isMultiLine ? 2 : 3)
    }

    /// An object or array that parses as JSON: code even on one line, where the score above would miss it.
    static func isJSON(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 1_000_000, (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]")),
              let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// A best guess at the language, only when the text says so clearly.
    static func language(of code: String) -> String? {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        if firstLine.hasPrefix("#!"), firstLine.contains("python") { return "Python" }
        if firstLine.hasPrefix("#!") || firstLine.hasPrefix("$ ") || shellPrefixes.contains(where: firstLine.hasPrefix) {
            return "Shell"
        }
        if isJSON(text) { return "JSON" }
        if text.hasPrefix("<"), text.hasSuffix(">") {
            return has("<html", "<div", "<body", "<head", "<span", "<!DOCTYPE", "<!doctype") ? "HTML" : "XML"
        }
        if has("import SwiftUI", "import Foundation", "import AppKit", "import UIKit", "guard let ", "if let ", "@State ",
               "func ") && !has("def ", "function ") { return "Swift" }
        if has("def ", "elif ", "self.", "import numpy", "__init__", "print(") && !has("{", ";") { return "Python" }
        if has("package main", "func main()", ":= ", "fmt.") { return "Go" }
        if has("fn ", "let mut ", "impl ", "pub fn", "::new(", "println!") { return "Rust" }
        if has("#include", "std::", "int main(", "printf(") { return "C" }
        if has("public static void", "System.out", "fun ", "val ") { return has("fun ", "val ") ? "Kotlin" : "Java" }
        if has("interface ", ": string", ": number", "as const") { return "TypeScript" }
        if has("function ", "=> ", "const ", "console.log", "document.", "require(", "export default") { return "JavaScript" }
        if has("SELECT ", "INSERT INTO", "CREATE TABLE", "UPDATE ", " WHERE ") { return "SQL" }
        if text.range(of: "^[.#]?[a-zA-Z][\\w-]*\\s*\\{[^}]*:[^}]*;", options: .regularExpression) != nil { return "CSS" }
        if has("puts ", "end\n", "do |") { return "Ruby" }
        return nil
    }
}

extension RGBAColor {
    /// A colour from three, four, six or eight hex digits, with or without the "#".
    public init?(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        self.init(red: Double((value >> (16 + shift)) & 0xFF) / 255,
                  green: Double((value >> (8 + shift)) & 0xFF) / 255,
                  blue: Double((value >> shift) & 0xFF) / 255,
                  alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }
}

/// Reads the few vCard fields a tile and its menu use. Folded lines are unfolded; parameters are dropped.
public enum VCard {
    public struct Field: Hashable, Sendable {
        public var key: String
        public var value: String
    }

    public static func fields(_ card: String) -> [Field] {
        let unfolded = card.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        return unfolded.split(separator: "\n").compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            var key = line[..<colon].split(separator: ";").first.map(String.init)?.uppercased() ?? ""
            if let dot = key.lastIndex(of: ".") { key = String(key[key.index(after: dot)...]) }
            let value = String(line[line.index(after: colon)...])
                .replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\,", with: ",")
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty, key != "BEGIN", key != "END", key != "VERSION" else { return nil }
            return Field(key: key, value: value)
        }
    }

    /// "Appleseed;Johnny;;Mr.;" → "Johnny Appleseed".
    static func nameFromN(_ value: String) -> String {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        let family = parts.first ?? ""
        let given = parts.count > 1 ? parts[1] : ""
        return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The values of one field: every phone number, every email.
    public static func values(_ key: String, in card: String) -> [String] {
        fields(card).filter { $0.key == key }.map(\.value)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
