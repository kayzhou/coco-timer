import AppKit
import UserNotifications

enum NotificationService {
    private static let restIdentifier = "yixi.rest"
    private static let workIdentifier = "yixi.work"

    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("含章可贞：通知权限请求失败：\(error.localizedDescription)")
            }
        }
    }

    /// - Parameter soundEnabled: 与「钟声」偏好一致；关闭时不附带系统通知音。
    static func notify(title: String, body: String, soundEnabled: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundEnabled ? .default : nil

        let identifier: String
        if title.contains("时止") {
            identifier = restIdentifier
        } else if title.contains("时行") {
            identifier = workIdentifier
        } else {
            identifier = "yixi.phase"
        }

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                NSLog("含章可贞：通知投递失败：\(error.localizedDescription)")
            }
        }
    }
}

@MainActor
enum SoundPlayer {
    private static var current: NSSound?

    static func playRestStart() {
        play("Glass")
    }

    static func playWorkStart() {
        play("Tink")
    }

    private static func play(_ name: String) {
        current = NSSound(named: name)
        current?.play()
    }
}
