import Foundation
#if os(iOS)
import CoreHaptics
#endif

/// 全局触感语义，参考 Yingchui 五级强度与双脉冲节奏规范：
/// L1=0.2, L2=0.4, L3=0.6, L4=0.8, L5=1.0；双脉冲间隔 100ms。
enum HapticIntent: Sendable {
    /// L1 (0.2)：选择项切换、相册勾选/滑选、滑动条刻度、开关切换
    case selection
    /// L2 (0.4)：普通按钮、图标、收起/展开、列表行点击
    case tap
    /// L3 (0.6)：主要操作（下拉刷新触发、置顶、重发、接收、连接）
    case action
    /// L4 (0.8)：危险或破坏性操作（删除、拒绝、取消传输、清缓存确认）
    case warning
    /// L3 -> L2 (0.6 -> 0.4, 100ms)：确认提交型操作（保存设置、提交发送、确认清缓存）
    case confirm
    /// L2 -> L3 (0.4 -> 0.6, 100ms)：真实异步结果完成（发送成功、刷新完成、复制成功、清理完成）
    case complete
    /// L5 (1.0)：真实错误与失败（发送失败、读取失败）
    case failure

    fileprivate var levels: [Int] {
        switch self {
        case .selection: return [1]
        case .tap: return [2]
        case .action: return [3]
        case .warning: return [4]
        case .confirm: return [3, 2]
        case .complete: return [2, 3]
        case .failure: return [5]
        }
    }
}

/// 独立队列上的 Core Haptics 触感引擎，不阻塞主线程；离前台自动暂停取消，不在后台补播。
final class Haptics {
    static let shared = Haptics()

    #if os(iOS)
    private let queue = DispatchQueue(label: "com.chongyang.quicktransfer.haptics")
    private var engine: CHHapticEngine?
    private var players: [Int: CHHapticPatternPlayer] = [:]
    private var nextID = 0
    private var active = true
    private static let intensities: [Float] = [0.2, 0.4, 0.6, 0.8, 1.0]
    private static let pulseIntervalSeconds: Double = 0.1
    #endif

    private init() {}

    func prepare() {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self else { return }
            self.active = true
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            try? self.ensureEngineStarted()
        }
        #endif
    }

    func suspend() {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self else { return }
            self.active = false
            for player in self.players.values {
                try? player.stop(atTime: CHHapticTimeImmediate)
            }
            self.players.removeAll()
        }
        #endif
    }

    func play(_ intent: HapticIntent) {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self, self.active else { return }
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            do {
                try self.ensureEngineStarted()
                guard let engine = self.engine else { return }
                let pattern = try Self.makePattern(for: intent)
                let player = try engine.makePlayer(with: pattern)
                self.nextID &+= 1
                let id = self.nextID
                self.players[id] = player
                try player.start(atTime: CHHapticTimeImmediate)
                self.queue.asyncAfter(deadline: .now() + 0.35) { [weak self, weak player] in
                    guard let self, let player, self.players[id] === player else { return }
                    self.players.removeValue(forKey: id)
                }
            } catch {
                // 触觉失败不影响业务流程
            }
        }
        #endif
    }

    #if os(iOS)
    private func ensureEngineStarted() throws {
        if engine == nil {
            let next = try CHHapticEngine()
            next.playsHapticsOnly = true
            next.isAutoShutdownEnabled = true
            next.resetHandler = { [weak self] in
                self?.queue.async {
                    self?.engine = nil
                    self?.players.removeAll()
                }
            }
            engine = next
        }
        try engine?.start()
    }

    private static func makePattern(for intent: HapticIntent) throws -> CHHapticPattern {
        let events = intent.levels.enumerated().map { index, level in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensities[level - 1]),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: Double(index) * pulseIntervalSeconds
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
    #endif
}
