import Foundation
import UserNotifications

/// Local notifications for fasts (no server jobs needed).
enum FastReminders {
    static func authorize() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func notifyEnd(of fast: Fast) async {
        guard await authorize() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Fast complete"
        content.body = "You reached your \(fast.targetMinutes / 60)-hour goal."
        let fireAt = fast.startedAt.addingTimeInterval(fast.target).timeIntervalSinceNow
        guard fireAt > 0 else { return }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fast-end-\(fast.id)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireAt, repeats: false)))
    }

    /// One repeating reminder per scheduled weekday.
    static func sync(_ schedules: [FastSchedule]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("fast-schedule-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !schedules.isEmpty, await authorize() else { return }
        for s in schedules {
            for d in s.weekdays {
                let content = UNMutableNotificationContent()
                content.title = "Time to start your fast"
                content.body = "\(s.targetMinutes / 60)-hour fast. Open mince to start the timer."
                var when = DateComponents()
                (when.weekday, when.hour, when.minute) = (d + 1, s.hour, s.minute)
                try? await center.add(UNNotificationRequest(identifier: "fast-schedule-\(s.id)-\(d)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
            }
        }
    }
}
