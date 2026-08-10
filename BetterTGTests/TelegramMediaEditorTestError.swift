// TelegramMediaEditorTestError.swift

enum TelegramMediaEditorTestError: Error {
    case imageContextCreationFailed
    case pixelBufferCreationFailed
    case writerFailed
    case writerInputRejected
    case writerNotReady
}
