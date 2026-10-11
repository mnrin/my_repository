import SwiftUI
import UserNotifications

struct ReminderNotificationPreferences {
    let enabled: Bool
    let breakfastEnabled: Bool
    let lunchEnabled: Bool
    let dinnerEnabled: Bool
    let eveningEnabled: Bool
    let breakfastMinutes: Int
    let lunchMinutes: Int
    let dinnerMinutes: Int
    let eveningMinutes: Int

    var hasAnyEnabledReminder: Bool {
        breakfastEnabled || lunchEnabled || dinnerEnabled || eveningEnabled
    }
}

enum ReminderNotificationScheduler {
    private struct Reminder {
        let id: String
        let enabled: Bool
        let minutesAfterMidnight: Int
        let title: String
        let body: String
    }

    private static let identifiers = [
        "mealReminder.breakfast",
        "mealReminder.lunch",
        "mealReminder.dinner",
        "dailyReminder.evening"
    ]

    static func apply(_ preferences: ReminderNotificationPreferences) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard preferences.enabled, preferences.hasAnyEnabledReminder else { return true }

        let settings = await center.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        default:
            isAuthorized = false
        }

        guard isAuthorized else { return false }

        let reminders = [
            Reminder(
                id: "mealReminder.breakfast",
                enabled: preferences.breakfastEnabled,
                minutesAfterMidnight: preferences.breakfastMinutes,
                title: "朝食を記録しませんか？",
                body: "食べたものを今日録に残しておきましょう。"
            ),
            Reminder(
                id: "mealReminder.lunch",
                enabled: preferences.lunchEnabled,
                minutesAfterMidnight: preferences.lunchMinutes,
                title: "昼食を記録しませんか？",
                body: "食べたものを今日録に残しておきましょう。"
            ),
            Reminder(
                id: "mealReminder.dinner",
                enabled: preferences.dinnerEnabled,
                minutesAfterMidnight: preferences.dinnerMinutes,
                title: "夕食を記録しませんか？",
                body: "食べたものを今日録に残しておきましょう。"
            ),
            Reminder(
                id: "dailyReminder.evening",
                enabled: preferences.eveningEnabled,
                minutesAfterMidnight: preferences.eveningMinutes,
                title: "今日の記録を振り返りましょう",
                body: "まだ記録していないことがあれば、無理のない範囲で追加できます。"
            )
        ]

        for reminder in reminders where reminder.enabled {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            var time = DateComponents()
            time.hour = reminder.minutesAfterMidnight / 60
            time.minute = reminder.minutesAfterMidnight % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                return false
            }
        }

        return true
    }
}
