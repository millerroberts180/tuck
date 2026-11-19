import Foundation

/// What a copy or a held item is, as the panel shows it: each has its own tile, and search can ask for
/// one by name ("images", "code yesterday"). How it was stored is separate: a date is still text.
public enum ContentCategory: String, Codable, CaseIterable, Sendable {
    case text
    /// Text whose styling (bold, italics, links) helps recognise it.
    case richText
    case code
    case link
    /// A link to a song, album or playlist on a music service.
    case music
    case email
    case phone
    case color
    /// A contact card (vCard).
    case contact
    /// A date (and perhaps a time) on its own, such as "8 November 2026" or "next Tuesday at 3".
    case date
    /// A postal address on its own.
    case address
    /// One or a few emoji and nothing else.
    case emoji
    /// The path of a file or folder, written out as text.
    case path
    /// An API key, token or private key: shown masked.
    case secret
    case image
    case screenshot
    case file
    case folder
    case audio
    case video
    /// Several files together.
    case stack
    /// A tucked window. Only search uses it, so "windows" can ask for them.
    case window

    /// The name a tile and search use: "Image", "Code".
    public var title: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich text"
        case .code: "Code"
        case .link: "Link"
        case .music: "Music"
        case .email: "Email"
        case .phone: "Phone number"
        case .color: "Color"
        case .contact: "Contact"
        case .date: "Date"
        case .address: "Address"
        case .emoji: "Emoji"
        case .path: "Path"
        case .secret: "Key"
        case .image: "Image"
        case .screenshot: "Screenshot"
        case .file: "File"
        case .folder: "Folder"
        case .audio: "Audio"
        case .video: "Video"
        case .stack: "Files"
        case .window: "Window"
        }
    }

    /// The name of a filter showing several: "Images", "Code".
    public var pluralTitle: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich text"
        case .code: "Code"
        case .music: "Music"
        case .phone: "Phone numbers"
        case .color: "Colors"
        case .address: "Addresses"
        case .emoji: "Emoji"
        case .secret: "Keys"
        case .audio: "Audio"
        case .stack: "Files"
        default: title + "s"
        }
    }

    /// Whether it is plain text underneath, which a click copies and the editor can change.
    public var isText: Bool {
        switch self {
        case .text, .richText, .code, .email, .phone, .color, .contact, .date, .address, .emoji, .path, .secret: true
        default: false
        }
    }
}

/// A colour in sRGB, each part 0...1.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#2F6FED", with the alpha as two more digits when it isn't opaque.
    public var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 1 ? byte(alpha) : "")
    }

    /// "rgb(47 111 237)", or with "/ 50%" when it isn't opaque, as CSS writes it.
    public var rgb: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let base = "rgb(\(byte(red)) \(byte(green)) \(byte(blue))"
        return alpha < 1 ? base + " / \(Int((alpha * 100).rounded()))%)" : base + ")"
    }

    /// Relative luminance (WCAG), for picking a legible mark over the colour.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// What the classifier recognised in a copy, kept with it so a tile draws without looking again.
public struct ContentRecognition: Codable, Hashable, Sendable {
    public var category: ContentCategory
    /// A colour's value.
    public var color: RGBAColor?
    /// A date's moment, and whether the text named a time of day too.
    public var date: Date?
    public var includesTime: Bool?
    /// The language code seems to be written in, when it is clear: "Swift", "Shell", "JSON".
    public var language: String?
    /// A contact's name, an emoji's Unicode name, or the kind of key ("Anthropic API key").
    public var name: String?
    /// A contact's organisation, or an address's lines after the first.
    public var detail: String?

    public init(category: ContentCategory, color: RGBAColor? = nil, date: Date? = nil, includesTime: Bool? = nil,
                language: String? = nil, name: String? = nil, detail: String? = nil) {
        self.category = category
        self.color = color
        self.date = date
        self.includesTime = includesTime
        self.language = language
        self.name = name
        self.detail = detail
    }

    public static let text = ContentRecognition(category: .text)
}
