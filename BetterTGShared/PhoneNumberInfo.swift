// PhoneNumberInfo.swift

import Foundation
import TDLibKit

// MARK: - PhoneNumberInfo

struct PhoneNumberInfo: Hashable, Identifiable {
    let country: String
    let phoneNumberPrefix: String
    let name: String

    var id: String {
        "\(country)-\(phoneNumberPrefix)"
    }

    var flagEmoji: String {
        let regionalIndicatorOffset: UInt32 = 127_397
        let scalars = country.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            return UnicodeScalar(regionalIndicatorOffset + scalar.value)
        }
        guard scalars.count == 2 else { return "🌐" }
        return String(String.UnicodeScalarView(scalars))
    }

    var accessibilityLabel: String {
        "\(flagEmoji) \(name), calling code plus \(phoneNumberPrefix)"
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || name.localizedCaseInsensitiveContains(query)
            || country.localizedCaseInsensitiveContains(query)
            || phoneNumberPrefix.localizedCaseInsensitiveContains(query)
            || "+\(phoneNumberPrefix)".localizedCaseInsensitiveContains(query)
    }
}

// MARK: - TelegramPhoneNumber

enum TelegramPhoneNumber {
    // MARK: Internal

    struct CallingCodeResolution: Sendable, Equatable {
        let callingCode: String
        let country: PhoneNumberInfo?
        let shouldAdvanceToNumber: Bool
    }

    static func countries(from countries: [CountryInfo]) -> [PhoneNumberInfo] {
        countries.compactMap(phoneNumberInfo).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func country(
        for countryCode: String?,
        in countries: [PhoneNumberInfo],
    ) -> PhoneNumberInfo? {
        guard let countryCode else { return nil }
        return countries.first { $0.country == countryCode }
    }

    static func normalized(callingCode: String, number: String) -> String? {
        let entered = number.filter { $0.isNumber || $0 == "+" }
        guard entered.contains(where: \.isNumber) else { return nil }
        if entered.hasPrefix("+") {
            return "+" + entered.dropFirst().filter(\.isNumber)
        }
        let prefix = callingCode.filter(\.isNumber)
        guard !prefix.isEmpty else { return nil }
        return "+\(prefix)\(entered.filter(\.isNumber))"
    }

    static func display(callingCode: String, number: String) -> String {
        let entered = number.filter { $0.isNumber || $0 == "+" }
        if entered.hasPrefix("+") {
            return entered
        }
        return "+\(callingCode.filter(\.isNumber)) \(entered.filter(\.isNumber))"
    }

    static func resolveCallingCode(
        _ value: String,
        countries: [PhoneNumberInfo],
        preferredCountryId: String?,
    ) -> CallingCodeResolution {
        let code = String(value.filter(\.isNumber).prefix(4))
        guard !code.isEmpty else {
            return CallingCodeResolution(callingCode: code, country: nil, shouldAdvanceToNumber: false)
        }
        let exactMatches = countries.filter { $0.phoneNumberPrefix == code }
        guard !exactMatches.isEmpty else {
            return CallingCodeResolution(callingCode: code, country: nil, shouldAdvanceToNumber: false)
        }
        let country = exactMatches.first { $0.country == preferredCountryId } ?? exactMatches.first
        let hasLongerCode = countries.contains {
            $0.phoneNumberPrefix.count > code.count && $0.phoneNumberPrefix.hasPrefix(code)
        }
        let preferredMatches = exactMatches.contains { $0.country == preferredCountryId }
        return CallingCodeResolution(
            callingCode: code,
            country: country,
            shouldAdvanceToNumber: !hasLongerCode || preferredMatches,
        )
    }

    // MARK: Private

    private static func phoneNumberInfo(_ country: CountryInfo) -> PhoneNumberInfo? {
        guard let callingCode = country.callingCodes.first else { return nil }
        return PhoneNumberInfo(
            country: country.countryCode,
            phoneNumberPrefix: callingCode,
            name: country.englishName,
        )
    }
}
