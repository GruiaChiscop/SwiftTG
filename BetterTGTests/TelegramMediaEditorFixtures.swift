// TelegramMediaEditorFixtures.swift

import Foundation

enum TelegramMediaEditorFixtures {
    // MARK: Internal

    static func tgsURL() throws -> URL {
        try fileURL(base64: visibleTgs, extension: "tgs")
    }

    static func webmURL() throws -> URL {
        try fileURL(base64: webm, extension: "webm")
    }

    // MARK: Private

    private static let visibleTgs = "H4sIAAAAAAAAA3VSwU7EIBC9+xVmzmRDo1sTPsAPUG8bDthSt2lLEVDTNPy7M5RouqRJ6cAb3ps3E1b4BgHn09OpBgadA/HAGfQWBIbZbscfEBXHeM3RTMgJvVmQ0rZtuqu818GDuEgGo1q0o/36l+4NxopBWEA8ZoUX3d6/fn4pp1HHu5QfkLbCTD+ViEOqGRm4HUaI3SGXM2f4cYkZtc8guuF+j1MzeclItDml/FVZvdknu+Aa6jPZuxGoOauTsC0KysJyRZ5z401Q5mPUEFmu0Y1Yo7mxR7ZZRUoHA6my4HM/jv9awcGRo3Iwx2MpO+AHTvxQXPOqgJLTN6eM72Y3QZTFO/MhHd8nIsh49wuls23cnQIAAA=="

    private static let webm = "GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQJChYECGFOAZwEAAAAAAAI9EU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHYTbuMU6uEElTDZ1OsggElTbuMU6uEHFO7a1OsggIn7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsirXsYMPQkBNgI1MYXZmNjIuMTIuMTAyV0GNTGF2ZjYyLjEyLjEwMkSJiEB/QAAAAAAAFlSua8iuAQAAAAAAAD/XgQFzxYia7vRFaoL7a5yBACK1nIN1bmSIgQCGhVZfVlA5g4EBI+ODhA7msoDgkLCBILqBIJqBAlWwhFW5gQESVMNnQIBzc6BjwIBnyJpFo4dFTkNPREVSRIeNTGF2ZjYyLjEyLjEwMnNz2mPAi2PFiJru9EVqgvtrZ8ilRaOHRU5DT0RFUkSHmExhdmM2Mi4yOC4xMDIgbGlidnB4LXZwOWfIoUWjiERVUkFUSU9ORIeTMDA6MDA6MDAuNTAwMDAwMDAwAB9DtnX354EAo96BAACAgkmDQgAB8AH2ADgkHBgAAADQfY69o8D+jqpxDvTAAHSeYMYZT64/ZdOU/E/t1H8jm1hXMHp8BUcrx2tSq7JXvU5448s1AsAlHkqVqe2iFe6eWf5RASjxWn0Ao5KBAPoAhgBAkpwAQAAAAgAAQ0AcU7trkbuPs4EAt4r3gQHxggGr8IED"

    private static func fileURL(base64: String, extension pathExtension: String) throws -> URL {
        guard let data = Data(base64Encoded: base64) else {
            throw TelegramMediaEditorTestError.fixtureDecodingFailed
        }
        let url = URL.temporaryDirectory
            .appending(path: "bettertg-editor-fixture-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try data.write(to: url)
        return url
    }
}
