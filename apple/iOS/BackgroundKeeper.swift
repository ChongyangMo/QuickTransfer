import UIKit
import UserNotifications

/// 离开前台后，在系统允许的后台时间内继续接收。
/// 使用系统提供的后台任务时间（通常约 30 秒），让正在进行的传输收完；
/// 时间用完前主动停止服务，回到前台时重新启动。不使用任何后台模式。
@MainActor
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()
    private let service = TransferService.shared
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var inBackground = false
    private var receivedFiles = 0
    private var notifyTimer: Timer?
    private static let filesNotification = "quicktransfer.received.files"

    private init() {}

    func prepare() {
        service.onReceive = { [weak self] name, text in self?.received(name:name,text:text) }
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) { _, _ in }
    }

    func enterForeground() {
        inBackground = false
        endTask()
        receivedFiles = 0
        notifyTimer?.invalidate(); notifyTimer = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:[Self.filesNotification])
    }

    /// 进入 inactive 或 background 时调用，可重复调用。
    func enterBackground() {
        guard !inBackground else { return }
        inBackground = true
        task = UIApplication.shared.beginBackgroundTask(withName:"QuickTransferReceive") { [weak self] in
            MainActor.assumeIsolated { self?.taskExpired() }
        }
        // 系统没有给后台时间时，立即停止，避免挂起后监听端口失效。
        if task == .invalid { service.stop() }
    }

    private func taskExpired() {
        // 即将被挂起：挂起后监听端口会被系统回收，先停止服务，回到前台时重新启动。
        flushFiles()
        if inBackground { service.stop() }
        endTask()
    }

    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }

    // MARK: 后台接收通知

    private func received(name: String, text: String?) {
        guard inBackground else { return }
        if let text {
            let content = UNMutableNotificationContent()
            content.title = name.isEmpty ? "收到文字" : "\(name) 发来文字"
            content.body = String(text.prefix(200))
            content.sound = .default
            post(UUID().uuidString,content)
            return
        }
        receivedFiles += 1
        notifyTimer?.invalidate()
        notifyTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushFiles() }
        }
    }

    private func flushFiles() {
        notifyTimer?.invalidate(); notifyTimer = nil
        guard inBackground, receivedFiles > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "快传"
        content.body = "已在后台收到 \(receivedFiles) 个文件"
        content.sound = .default
        post(Self.filesNotification,content)
    }

    private func post(_ id: String, _ content: UNMutableNotificationContent) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:id,content:content,trigger:nil)) { _ in }
    }
}
