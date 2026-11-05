import Foundation

/// A calendar day in the user's current time zone, stored as `yyyy-MM-dd`
/// (Postgres `date`). The device decides what "today" is, never the server,
/// so logging at 11pm never lands on tomorrow.
struct Day: Hashable, Comparable, Codable, Identifiable, CustomStringConvertible {
    let rawValue: String
    var id: String { rawValue }
    var description: String { rawValue }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(_ date: Date = Date()) {
        Self.formatter.timeZone = .current
        rawValue = Self.formatter.string(from: date)
    }

    init?(rawValue: String) {
        guard Self.formatter.date(from: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    static var today: Day { Day() }

    /// Noon on this day, local time (safe from DST edges).
    var date: Date {
        Self.formatter.timeZone = .current
        let midnight = Self.formatter.date(from: rawValue) ?? Date()
        return Calendar.current.date(byAdding: .hour, value: 12, to: midnight) ?? midnight
    }

    func adding(days: Int) -> Day {
        Day(Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Days from `self` to `other` (positive when other is later).
    func distance(to other: Day) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    /// 0 = Sunday ... 6 = Saturday, matching Postgres `extract(dow ...)`.
    var weekday: Int { Calendar(identifier: .gregorian).component(.weekday, from: date) - 1 }

    var isToday: Bool { self == .today }

    var title: String {
        switch Day.today.distance(to: self) {
        case 0: "Today"
        case -1: "Yesterday"
        case 1: "Tomorrow"
        default: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    static func < (lhs: Day, rhs: Day) -> Bool { lhs.rawValue < rhs.rawValue }

    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(rawValue: String(s.prefix(10))) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}
