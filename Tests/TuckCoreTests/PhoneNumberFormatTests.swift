import Foundation
import Testing
@testable import TuckCore

@Suite("Phone numbers")
struct PhoneNumberFormatTests {
    private func format(_ text: String, region: String? = "US") -> String? {
        PhoneNumberFormat.parse(text, defaultRegion: region)?.formatted
    }

    @Test func northAmericanNumbersReadAsTheyAreWritten() {
        #expect(format("+1 (415) 555-0132") == "+1 (415) 555-0132")
        #expect(format("+14155550132") == "+1 (415) 555-0132")
        #expect(format("650.555.0199") == "(650) 555-0199")
        #expect(format("1-650-555-0199") == "(650) 555-0199")
        let number = PhoneNumberFormat.parse("+1 (415) 555-0132", defaultRegion: "GB")
        #expect(number?.callingCode == "1")
        #expect(number?.nationalFormatted == "(415) 555-0132")
        #expect(number?.region == "US")
    }

    @Test func aCanadianAreaCodeRingsInCanada() {
        #expect(PhoneNumberFormat.parse("+1 416 555 0199", defaultRegion: nil)?.region == "CA")
        #expect(PhoneNumberFormat.parse("(604) 555-0100", defaultRegion: "US")?.region == "CA")
        #expect(PhoneNumberFormat.region(forCallingCode: "1", nationalNumber: "2125550100") == "US")
    }

    @Test func knownCountriesAreGroupedTheirWay() {
        #expect(format("+44 20 7946 0958") == "+44 20 7946 0958")
        #expect(format("+442079460958") == "+44 20 7946 0958")
        #expect(format("+44 (0)20 7946 0958") == "+44 20 7946 0958")
        #expect(format("+44 7700 900123") == "+44 7700 900123")
        #expect(format("+44 121 496 0000") == "+44 121 496 0000")
        #expect(format("+33 6 12 34 56 78") == "+33 6 12 34 56 78")
        #expect(format("+49 30 12345678") == "+49 30 12345678")
        #expect(format("+81 90 1234 5678") == "+81 90 1234 5678")
        #expect(format("+91 98765 43210") == "+91 98765 43210")
        #expect(format("+61 412 345 678") == "+61 412 345 678")
        #expect(format("+7 912 345 67 89") == "+7 912 345 67 89")
        #expect(format("+353 85 123 4567") == "+353 85 123 4567")
        #expect(format("+971 50 123 4567") == "+971 50 123 4567")
    }

    @Test func otherNumbersAreGroupedInThreesAndFours() {
        #expect(format("+999 123 4567") == "+999 123 4567")
        #expect(format("+34 912 345 678") == "+34 912 345 678")
        #expect(format("555 0132", region: nil) == "555 0132")
        #expect(format("12345678", region: nil) == "1234 5678")
        #expect(format("0123456789", region: "IT") == "012 345 6789")
        #expect(PhoneNumberFormat.genericGroups(14) == [3, 3, 4, 4])
    }

    @Test func aNumberWithoutACodeRingsInTheMacsRegion() {
        let london = PhoneNumberFormat.parse("020 7946 0958", defaultRegion: "GB")
        #expect(london?.region == "GB")
        #expect(london?.nationalNumber == "2079460958")
        #expect(london?.formatted == "020 7946 0958")
        #expect(london?.isInternational == false)
        // An international prefix dialled from there names the country after it.
        #expect(PhoneNumberFormat.parse("0044 20 7946 0958", defaultRegion: "FR")?.formatted == "+44 20 7946 0958")
        #expect(PhoneNumberFormat.parse("011 44 20 7946 0958", defaultRegion: "US")?.region == "GB")
        // With no region to go by, the number has no country.
        let unknown = PhoneNumberFormat.parse("650.555.0199", defaultRegion: nil)
        #expect(unknown?.region == nil)
        #expect(unknown?.flag == nil)
        #expect(PhoneNumberFormat.parse("call me", defaultRegion: "US") == nil)
    }

    @Test func aCallingCodeNamesItsRegionAndFlag() {
        #expect(PhoneNumberFormat.parse("+44 20 7946 0958", defaultRegion: nil)?.flag == "🇬🇧")
        #expect(PhoneNumberFormat.parse("+81 3 1234 5678", defaultRegion: nil)?.region == "JP")
        #expect(PhoneNumberFormat.parse("+7 701 123 4567", defaultRegion: nil)?.region == "KZ")
        #expect(PhoneNumberFormat.parse("+999 123 4567", defaultRegion: nil)?.region == nil)
        #expect(PhoneNumberFormat.flag(forRegion: "us") == "🇺🇸")
        #expect(PhoneNumberFormat.flag(forRegion: "USA") == nil)
        #expect(PhoneNumberFormat.flag(forRegion: "1A") == nil)
        for (region, code) in PhoneNumberFormat.callingCodes {
            #expect(PhoneNumberFormat.flag(forRegion: region) != nil, "\(region)")
            #expect(!code.isEmpty && code.allSatisfy(\.isNumber), "\(region)")
        }
    }
}
