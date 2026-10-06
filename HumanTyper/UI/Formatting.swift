import Foundation

enum Formatting {
    /// «2:05» или «1:02:03».
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// «1 символ», «3 символа», «25 символов».
    static func characters(_ count: Int) -> String {
        "\(count) \(plural(count, one: "символ", few: "символа", many: "символов"))"
    }

    static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let mod100 = abs(count) % 100
        let mod10 = mod100 % 10
        if (11...14).contains(mod100) { return many }
        switch mod10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
