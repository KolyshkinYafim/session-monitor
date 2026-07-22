import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyIfNeeded(session: SessionMeta, status: SessionStatus, previous: SessionStatus?) {
        guard previous != status else { return }
        guard status == .waitingInput || status == .done || status == .error else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(statusTitle(status)) · \(session.provider)"
        content.body = session.title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(session.id)-\(status.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func statusTitle(_ status: SessionStatus) -> String {
        switch status {
        case .waitingInput: "Needs input"
        case .done: "Done"
        case .error: "Error"
        default: status.label
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
