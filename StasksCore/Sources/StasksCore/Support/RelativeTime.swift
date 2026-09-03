import Foundation

public enum RelativeTime {
    /// `nowLabel` is the sub-minute label; the app passes it localized. The unit suffixes (m, h, d) are language neutral.
    public static func label(from: Date, to now: Date, nowLabel: String = "now") -> String {
        let s = max(0, now.timeIntervalSince(from))
        if s < 60 { return nowLabel }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
