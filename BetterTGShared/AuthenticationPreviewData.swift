// AuthenticationPreviewData.swift

enum AuthenticationPreviewData {
    static let countries = [
        PhoneNumberInfo(country: "RO", phoneNumberPrefix: "40", name: "Romania"),
        PhoneNumberInfo(country: "GB", phoneNumberPrefix: "44", name: "United Kingdom"),
        PhoneNumberInfo(country: "US", phoneNumberPrefix: "1", name: "United States"),
    ]

    static let codeLength = 6
    static let passwordHint = "Debug password"
    static let phoneNumber = "721234567"
}
