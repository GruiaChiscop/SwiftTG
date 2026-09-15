// TelegramVoiceSkipSettings.swift

import Foundation

/// How far Skip Forward/Backward move within a voice message - fully automatic, based on the
/// user's own observation of WhatsApp's behavior: short notes step by a small amount, longer ones
/// by progressively bigger ones, and repeated taps always land exactly on 0 or the end rather than
/// overshooting into a clamp on the last tap. Not a user-facing setting - they explicitly didn't
/// want to configure this themselves.
enum TelegramVoiceSkipSettings {
    /// The next Skip Forward/Backward landing position from `current`, in seconds - stepped by
    /// `nominalStep(forDuration:)`, but adjusted so `duration / step` divides evenly, so the exact
    /// same step size applied repeatedly from 0 always lands precisely on `duration` on the last
    /// tap instead of overshooting into a clamp (and therefore an oddly small final step).
    static func nextPosition(from current: Double, duration: Int, forward: Bool) -> Double {
        guard duration > 0 else { return 0 }
        let nominal = Double(nominalStep(forDuration: duration))
        let totalSteps = max(1, (Double(duration) / nominal).rounded())
        let step = Double(duration) / totalSteps
        let target = forward ? current + step : current - step
        return forward ? min(Double(duration), target) : max(0, target)
    }

    /// Approximates the user's own tested WhatsApp observation: 1-10s notes step by 1s, 11-60s by
    /// 3s, longer ones by 6s. The exact tier boundaries/values above 10s weren't fully certain
    /// ("cred că ajunge la 6") - adjust if a real device test shows otherwise.
    private static func nominalStep(forDuration duration: Int) -> Int {
        switch duration {
        case ...10: 1
        case 11...60: 3
        default: 6
        }
    }
}
