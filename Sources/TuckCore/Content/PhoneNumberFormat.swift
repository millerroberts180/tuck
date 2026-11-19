import Foundation

/// A copied phone number, read for showing: its country calling code when it has one or the region
/// implies it, the number after that code, and where it rings.
public struct PhoneNumber: Equatable, Sendable {
    /// The country calling code without its "+": "1", "44".
    public let callingCode: String?
    /// The digits after the calling code, without a trunk prefix: "4155550132", "2079460958".
    public let nationalNumber: String
    /// The ISO 3166 region the number belongs to ("US", "GB"), when its code or the Mac's region says.
    public let region: String?
    /// Whether it was written with its calling code ("+44…", "0044…"), and so is shown with it.
    public let isInternational: Bool

    /// The number grouped as it is written where it rings, after its code: "(415) 555-0132", "20 7946
    /// 0958". Written without a code, it keeps its trunk prefix: "020 7946 0958".
    public var nationalFormatted: String {
        let grouped = PhoneNumberFormat.grouped(nationalNumber, callingCode: callingCode)
        guard !isInternational, let callingCode, let trunk = PhoneNumberFormat.trunkPrefixes[callingCode] else {
            return grouped
        }
        return trunk + grouped
    }

    /// "+1 (415) 555-0132", "+44 20 7946 0958"; written without a code, as `nationalFormatted`.
    public var formatted: String {
        guard isInternational else { return nationalFormatted }
        guard let callingCode else { return "+" + nationalFormatted }
        return "+\(callingCode) \(nationalFormatted)"
    }

    /// The region's flag, "🇬🇧".
    public var flag: String? { region.flatMap(PhoneNumberFormat.flag(forRegion:)) }
}

/// Reads phone numbers the way people write them and groups them for reading. Only formatting: what
/// is dialled or texted is the digits as copied.
public enum PhoneNumberFormat {
    /// Each region's country calling code.
    public static let callingCodes: [String: String] = [
        "US": "1", "CA": "1", "GB": "44", "FR": "33", "DE": "49", "ES": "34", "IT": "39", "JP": "81", "KR": "82",
        "CN": "86", "IN": "91", "AU": "61", "MX": "52", "BR": "55", "NL": "31", "SE": "46", "CH": "41",
        "IE": "353", "RU": "7", "KZ": "7", "ZA": "27", "SG": "65", "AE": "971", "NZ": "64", "BE": "32",
        "AT": "43", "DK": "45", "NO": "47", "FI": "358", "PL": "48", "PT": "351", "GR": "30", "TR": "90",
        "IL": "972", "HK": "852", "TW": "886", "PH": "63", "TH": "66", "MY": "60", "ID": "62", "VN": "84",
        "AR": "54", "CL": "56", "CO": "57", "PE": "51", "EG": "20", "NG": "234", "KE": "254", "SA": "966",
        "PK": "92", "BD": "880", "UA": "380", "CZ": "420", "HU": "36", "RO": "40",
    ]

    /// What is dialled before a number inside its own country, by calling code. North America's 1 is
    /// read apart, and Italy keeps its 0 as part of the number, so neither is here.
    static let trunkPrefixes: [String: String] = [
        "44": "0", "33": "0", "49": "0", "81": "0", "82": "0", "86": "0", "91": "0", "61": "0",
        "55": "0", "31": "0", "46": "0", "41": "0", "353": "0", "7": "8", "27": "0", "971": "0", "64": "0",
        "32": "0", "43": "0", "358": "0", "90": "0", "972": "0", "886": "0", "63": "0", "66": "0", "60": "0",
        "62": "0", "84": "0", "54": "0", "51": "0", "20": "0", "234": "0", "254": "0", "966": "0", "92": "0",
        "880": "0", "380": "0",
    ]

    /// Area codes of the North American plan that ring in Canada; the rest of +1 is taken as the US.
    static let canadianAreaCodes: Set<String> = [
        "204", "226", "236", "249", "250", "257", "263", "273", "289", "306", "343", "354", "365", "367", "368",
        "382", "403", "416", "418", "428", "431", "437", "438", "450", "460", "468", "474", "506", "514", "519",
        "548", "579", "581", "584", "587", "604", "613", "639", "647", "672", "683", "705", "709", "742", "753",
        "778", "780", "782", "807", "819", "825", "867", "873", "879", "902", "905", "942",
    ]

    /// Reads a written number. With a "+" (or "00", or "011" in North America) the calling code is read
    /// from it; without, the number is taken to ring in `defaultRegion`, the Mac's region. Nil when the
    /// text has no digits.
    public static func parse(_ text: String, defaultRegion: String?) -> PhoneNumber? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = trimmed.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let homeCode = defaultRegion.flatMap { callingCodes[$0.uppercased()] }

        var isInternational = trimmed.hasPrefix("+")
        if !isInternational, digits.hasPrefix("00") {
            digits.removeFirst(2)
            isInternational = true
        } else if !isInternational, homeCode == "1", digits.hasPrefix("011") {
            digits.removeFirst(3)
            isInternational = true
        }

        if isInternational {
            guard let code = (1...3).lazy.map({ String(digits.prefix($0)) }).first(where: { regions[$0] != nil }),
                  digits.count > code.count else {
                return PhoneNumber(callingCode: nil, nationalNumber: digits, region: nil, isInternational: true)
            }
            let national = withoutTrunk(String(digits.dropFirst(code.count)), callingCode: code)
            return PhoneNumber(callingCode: code, nationalNumber: national,
                               region: region(forCallingCode: code, nationalNumber: national), isInternational: true)
        }

        guard let homeCode, let home = defaultRegion?.uppercased() else {
            return PhoneNumber(callingCode: nil, nationalNumber: digits, region: nil, isInternational: false)
        }
        let national = homeCode == "1" && digits.count == 11 && digits.hasPrefix("1")
            ? String(digits.dropFirst()) : withoutTrunk(digits, callingCode: homeCode)
        // A North American number names its own side of the border.
        let rings = homeCode == "1" ? region(forCallingCode: "1", nationalNumber: national) : home
        return PhoneNumber(callingCode: homeCode, nationalNumber: national, region: rings, isInternational: false)
    }

    /// The region a number rings in, from its calling code and, where a code is shared, its first digits.
    public static func region(forCallingCode code: String, nationalNumber: String) -> String? {
        switch code {
        case "1": return canadianAreaCodes.contains(String(nationalNumber.prefix(3))) ? "CA" : "US"
        case "7": return nationalNumber.hasPrefix("6") || nationalNumber.hasPrefix("7") ? "KZ" : "RU"
        default: return regions[code]
        }
    }

    /// A region's flag emoji, from its two letters: "GB" "🇬🇧". Nil for anything that isn't two letters A–Z.
    public static func flag(forRegion region: String) -> String? {
        let letters = region.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        return String(String.UnicodeScalarView(letters.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
    }

    /// Each calling code's region; the two codes shared by several regions are told apart by their digits.
    private static let regions = Dictionary(callingCodes.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

    private static func withoutTrunk(_ digits: String, callingCode: String) -> String {
        guard let trunk = trunkPrefixes[callingCode], digits.hasPrefix(trunk),
              digits.count > trunk.count + 5 else { return digits }
        return String(digits.dropFirst(trunk.count))
    }

    /// The digits after a calling code, grouped as that country writes them; any other number in groups of
    /// three and four.
    static func grouped(_ digits: String, callingCode: String?) -> String {
        let count = digits.count
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { digits.hasPrefix($0) } }
        var sizes: [Int]?
        switch (callingCode, count) {
        case ("1", 10):
            let parts = split(digits, [3, 3, 4])
            return "(\(parts[0])) \(parts[1])-\(parts[2])"
        case ("44", 10):
            // London's 20, a mobile's 7, the big cities' 1x1 and 11x, and everywhere else's four.
            if starts("2") {
                sizes = [2, 4, 4]
            } else if !starts("7"), starts("3", "8", "9") || digits.dropFirst().prefix(2).contains("1") {
                sizes = [3, 3, 4]
            } else {
                sizes = [4, 6]
            }
        case ("33", 9): sizes = [1, 2, 2, 2, 2]
        case ("49", 9...11): sizes = starts("30", "40", "69", "89") ? [2, count - 2] : [3, count - 3]
        case ("34", 9): sizes = [3, 3, 3]
        case ("81", 10): sizes = [2, 4, 4]
        case ("81", 9): sizes = starts("3", "6") ? [1, 4, 4] : [2, 3, 4]
        case ("82", 10): sizes = [2, 4, 4]
        case ("82", 9) where starts("2"): sizes = [1, 4, 4]
        case ("86", 11) where starts("1"): sizes = [3, 4, 4]
        case ("86", 10): sizes = [2, 4, 4]
        case ("91", 10): sizes = [5, 5]
        case ("61", 9): sizes = starts("4") ? [3, 3, 3] : [1, 4, 4]
        case ("52", 10): sizes = starts("55", "33", "81") ? [2, 4, 4] : [3, 3, 4]
        case ("55", 11): sizes = [2, 5, 4]
        case ("55", 10): sizes = [2, 4, 4]
        case ("31", 9): sizes = starts("6") ? [1, 4, 4] : (starts("10", "20", "30", "70") ? [2, 3, 4] : [3, 3, 3])
        case ("46", 9) where starts("7"): sizes = [2, 3, 2, 2]
        case ("41", 9): sizes = [2, 3, 2, 2]
        case ("353", 9) where starts("8"): sizes = [2, 3, 4]
        case ("353", 8) where starts("1"): sizes = [1, 3, 4]
        case ("7", 10): sizes = [3, 3, 2, 2]
        case ("27", 9): sizes = [2, 3, 4]
        case ("65", 8): sizes = [4, 4]
        case ("971", 9) where starts("5"): sizes = [2, 3, 4]
        case ("971", 8): sizes = [1, 3, 4]
        default: break
        }
        return split(digits, sizes ?? genericGroups(count)).joined(separator: " ")
    }

    /// Groups of three and four: "555 0132", "1234 5678", "123 456 7890".
    static func genericGroups(_ count: Int) -> [Int] {
        switch count {
        case ...5: return [count]
        case 6: return [3, 3]
        case 7: return [3, 4]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        case 10: return [3, 3, 4]
        case 11: return [3, 4, 4]
        case 12: return [4, 4, 4]
        default: return [3] + genericGroups(count - 3)
        }
    }

    private static func split(_ digits: String, _ sizes: [Int]) -> [String] {
        var rest = Substring(digits)
        var parts: [String] = []
        for size in sizes where !rest.isEmpty {
            parts.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }
}
