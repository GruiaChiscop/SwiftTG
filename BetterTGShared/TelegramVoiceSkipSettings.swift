// TelegramVoiceSkipSettings.swift

import Foundation

/// How far Skip Forward/Backward move within a voice message - fully automatic, based on the
/// user's own observation of WhatsApp's behavior: short notes step by a small amount, longer ones
/// by progressively bigger ones, and repeated taps always land exactly on 0 or the end rather than
/// overshooting into a clamp on the last tap. Not a user-facing setting - they explicitly didn't
/// want to configure this themselves.
enum TelegramVoiceSkipSettings {
    // MARK: Internal

    /// The next Skip Forward/Backward landing position from `current`, snapped to the nearest
    /// checkpoint in `checkpoints(forDuration:)` past it - see that function for how the step sizes
    /// stay whole seconds (mostly the nominal amount, occasionally one second more) while still
    /// landing exactly on 0/`duration` at the ends.
    static func nextPosition(from current: Double, duration: Int, forward: Bool) -> Double {
        guard duration > 0 else { return 0 }
        let points = checkpoints(forDuration: duration)
        if forward {
            return points.first { Double($0) > current + 0.01 }.map(Double.init) ?? Double(duration)
        }
        // Rewind past the displayed whole second. At 4.8s, jumping to 4s only
        // restarts that second; short notes must go back to 3s instead.
        return points.last { Double($0) < floor(current) - 0.01 }.map(Double.init) ?? 0
    }

    // MARK: Private

    /// Whole-second landing positions from 0 to `duration`, `totalSteps` apart - each gap is
    /// `nominalStep(forDuration:)` seconds, rounded up or down by at most one second so
    /// `totalSteps` of them sum to exactly `duration` (the standard "distribute N items into M
    /// nearly-equal integer buckets" trick: position `i` is `round(i * duration / totalSteps)`,
    /// which guarantees each individual gap is one of only two consecutive integers). Matches the
    /// user's own tested example closely (a 61s note: 0, 6, 12, 18, 24, 31, 37, 43, 49, 55, 61 -
    /// mostly 6s steps, one 7).
    private static func checkpoints(forDuration duration: Int) -> [Int] {
        let nominal = nominalStep(forDuration: duration)
        let totalSteps = max(1, Int((Double(duration) / Double(nominal)).rounded()))
        return (0...totalSteps).map { index in
            Int((Double(index) * Double(duration) / Double(totalSteps)).rounded())
        }
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
