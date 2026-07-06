import Foundation

/// working状態の経過時間表示の書式化。最小単位の整数+単位（19s/90m/2h）。
/// 境界: <60s→s, <60m→m, ≥60m→h。
public enum WorkingElapsedFormatter {
    public static func format(seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h"
    }
}
