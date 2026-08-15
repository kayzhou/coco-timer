import AppKit
import UserNotifications

enum NotificationService {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("含章可贞：通知权限请求失败：\(error.localizedDescription)")
            }
        }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "yixi.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
