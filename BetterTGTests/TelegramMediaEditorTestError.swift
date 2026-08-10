// TelegramMediaEditorTestError.swift

enum TelegramMediaEditorTestError: Error {
    case fixtureDecodingFailed
    case imageContextCreationFailed
    case pixelBufferCreationFailed
    case writerFailed
    case writerInputRejected
    case writerNotReady
}
