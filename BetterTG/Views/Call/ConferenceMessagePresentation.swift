// ConferenceMessagePresentation.swift

import Foundation
import TDLibKit

// MARK: - ConferenceMessagePresentation

struct ConferenceMessagePresentation: Equatable, Identifiable {
    let id: Int
    let userId: Int64?
    let chatId: Int64?
    let formattedText: FormattedText
    let date: Foundation.Date
}
