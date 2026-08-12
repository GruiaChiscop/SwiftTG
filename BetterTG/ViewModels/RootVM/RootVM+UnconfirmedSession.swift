// RootVM+UnconfirmedSession.swift

import TDLibKit

extension RootVM {
    @MainActor func confirmUnconfirmedSession() {
        guard let sessionId = Self.deviceSessionId(unconfirmedSession), !isProcessingUnconfirmedSession
        else { return }
        isProcessingUnconfirmedSession = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isProcessingUnconfirmedSession = false }
            do {
                _ = try await service.confirmSession(sessionId: sessionId)
                unconfirmedSession = nil
            } catch {
                unconfirmedSessionActionError = telegramErrorDescription(error)
            }
        }
    }

    @MainActor func denyUnconfirmedSession() {
        guard let sessionId = Self.deviceSessionId(unconfirmedSession), !isProcessingUnconfirmedSession
        else { return }
        isProcessingUnconfirmedSession = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isProcessingUnconfirmedSession = false }
            do {
                _ = try await service.terminateSession(sessionId: sessionId)
                unconfirmedSession = nil
                showsDeniedSessionNotice = true
            } catch {
                unconfirmedSessionActionError = telegramErrorDescription(error)
            }
        }
    }

    /// Only `.sessionTypeDevice` carries a session id `confirmSession`/`terminateSession` can act
    /// on - see `TelegramUnconfirmedSessionBannerView`'s doc comment for the connected-bot case.
    static func deviceSessionId(_ session: UnconfirmedSession?) -> TdInt64? {
        guard case .sessionTypeDevice(let device) = session?.type else { return nil }
        return device.sessionId
    }
}
